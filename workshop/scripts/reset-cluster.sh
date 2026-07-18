#!/usr/bin/env bash
# Reset training cluster (destroy-only): remove Aerospike database and all workload nodegroups/NodePools.
# Preserves EKS control plane, AKO, storage layer, and secrets.
#
# Usage:
#   ./scripts/reset-cluster.sh              # interactive confirm
#   ./scripts/reset-cluster.sh --yes        # skip prompt
#   ./scripts/reset-cluster.sh --upgrade-lab  # target upgrade-lab cluster (always eksctl MNG)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/nodepool-zones.sh"
source "$(dirname "$0")/lib/karpenter-teardown.sh"
load_env

POD_WAIT_TIMEOUT=300

usage() {
  cat <<EOF
Usage: $(basename "$0") [--yes] [--upgrade-lab]

Destroy Aerospike workload and all workload nodegroups/NodePools on the training cluster.
Keeps the EKS control plane, AKO operator, storage, and secrets intact.

Options:
  --yes          Skip confirmation prompt
  --upgrade-lab  Target UPGRADE_LAB_CLUSTER_NAME (eksctl MNG only)
  -h, --help     Show this help

To re-bootstrap nodes after reset:
  ./scripts/labs/prepare-lab.sh 1.1    # or lab-nodes.sh 1.1 ensure

For full EKS cluster deletion, use ./scripts/cleanup-lab.sh instead.
EOF
}

assume_yes=false
upgrade_lab=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) assume_yes=true ;;
    --upgrade-lab) upgrade_lab=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

require_cmd kubectl
require_cmd eksctl
require_cmd aws

: "${UPGRADE_LAB_CLUSTER_NAME:=my-cluster-k8s-upgrade}"
: "${UPGRADE_LAB_NODEGROUP_NAME:=ng-upgrade-lab}"

if [[ "${upgrade_lab}" == true ]]; then
  TARGET_CLUSTER="${UPGRADE_LAB_CLUSTER_NAME}"
  PROVISIONING="eksctl"
else
  TARGET_CLUSTER="${CLUSTER_NAME}"
  PROVISIONING="${NODE_PROVISIONING}"
fi

if ! cluster_exists "${TARGET_CLUSTER}"; then
  echo "ERROR: EKS cluster '${TARGET_CLUSTER}' not found in ${AWS_REGION}" >&2
  exit 1
fi

if [[ "${upgrade_lab}" == true ]]; then
  ensure_upgrade_lab_kubecontext
else
  ensure_main_kubecontext
fi

list_eksctl_nodegroups() {
  eksctl get nodegroup \
    --cluster="${TARGET_CLUSTER}" \
    --region="${AWS_REGION}" \
    -o json 2>/dev/null \
    | python3 -c 'import json,sys; data=json.load(sys.stdin); print("\n".join(n["Name"] for n in data))' 2>/dev/null || true
}

print_plan() {
  echo "=== Reset plan ==="
  echo "Cluster:      ${TARGET_CLUSTER} (${AWS_REGION})"
  echo "Provisioning: ${PROVISIONING}"
  echo ""
  echo "Will delete:"
  echo "  - AerospikeCluster aerocluster (and local-ssd-demo if present)"
  if [[ "${DEPLOY_PATH}" == "helm" ]]; then
    echo "  - Helm release ${HELM_CLUSTER_RELEASE} in ${NAMESPACE}"
  fi
  echo "  - Stuck PV claimRefs in ${NAMESPACE}"
  if [[ "${PROVISIONING}" == "karpenter" ]]; then
    local pool
    while IFS= read -r pool; do
      [[ -z "${pool}" ]] && continue
      echo "  - NodePool ${pool}"
    done < <(list_baseline_pool_names; list_vertical_pool_names)
    echo "  - Per-zone karpenter-bootstrap-* Deployments (if present)"
    echo "  - Per-zone karpenter-vertical-bootstrap-* Deployments (if present)"
    echo ""
    echo "Will preserve:"
    echo "  - System nodegroup ${KARPENTER_SYSTEM_NODEGROUP}"
    echo "  - Karpenter controller and EC2NodeClass ${KARPENTER_NODECLASS_NAME}"
  else
    local found=false name
    while IFS= read -r name; do
      [[ -z "${name}" ]] && continue
      echo "  - Nodegroup ${name}"
      found=true
    done < <(list_eksctl_nodegroups)
    if [[ "${found}" == false ]]; then
      echo "  - (no nodegroups found)"
    fi
  fi
  echo ""
  echo "Will preserve:"
  echo "  - EKS control plane"
  echo "  - AKO operator (${OPERATOR_NAMESPACE})"
  echo "  - Storage layer and secrets (${NAMESPACE})"
}

confirm_reset() {
  if [[ "${assume_yes}" == true ]]; then
    return 0
  fi
  print_plan
  echo ""
  read -r -p "Proceed with reset? [y/N] " reply
  case "${reply}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) echo "Aborted."; exit 0 ;;
  esac
}

teardown_database() {
  echo "=== Phase 1: Teardown database ==="

  if [[ "${DEPLOY_PATH}" == "helm" ]]; then
    echo "Uninstalling Helm release ${HELM_CLUSTER_RELEASE}..."
    helm uninstall "${HELM_CLUSTER_RELEASE}" -n "${NAMESPACE}" 2>/dev/null || true
  else
    echo "Deleting AerospikeCluster aerocluster..."
    kubectl delete aerospikecluster aerocluster -n "${NAMESPACE}" --ignore-not-found
  fi
  kubectl delete aerospikecluster local-ssd-demo -n "${NAMESPACE}" --ignore-not-found

  echo "Waiting for Aerospike pods to terminate (timeout ${POD_WAIT_TIMEOUT}s)..."
  deadline=$((SECONDS + POD_WAIT_TIMEOUT))
  while true; do
    remaining="$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null \
      | awk '$1 ~ /^aerocluster/ || $1 ~ /^local-ssd-demo/' | wc -l | tr -d ' ')"
    if [[ "${remaining}" -eq 0 ]]; then
      break
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      echo "ERROR: timed out waiting for Aerospike pods to terminate (${remaining} remaining)" >&2
      kubectl get pods -n "${NAMESPACE}" -o wide
      exit 1
    fi
    echo "  ${remaining} Aerospike pod(s) still terminating..."
    sleep 10
  done

  echo "Releasing stuck PV claimRefs..."
  local pv_list
  pv_list="$(kubectl get pv --no-headers 2>/dev/null | awk -v ns="${NAMESPACE}" 'index($0, ns) {print $1}')" || true
  while IFS= read -r pv; do
    [[ -z "${pv}" ]] && continue
    kubectl patch pv "${pv}" -p '{"spec":{"claimRef": null}}' 2>/dev/null || true
  done <<< "${pv_list}"

  echo "Database teardown complete."
}

delete_eksctl_nodegroups() {
  echo "=== Phase 2: Delete eksctl managed nodegroups ==="

  local found=false ng
  while IFS= read -r ng; do
    [[ -z "${ng}" ]] && continue
    found=true
    echo "Deleting nodegroup ${ng}..."
    eksctl delete nodegroup \
      --cluster="${TARGET_CLUSTER}" \
      --region="${AWS_REGION}" \
      --name="${ng}" \
      --drain=false \
      --wait
  done < <(list_eksctl_nodegroups)

  if [[ "${found}" == false ]]; then
    echo "No nodegroups found — nothing to delete."
    return 0
  fi

  echo "All nodegroups deleted."
}

delete_karpenter_workload() {
  echo "=== Phase 2: Delete Karpenter workload NodePools ==="
  drain_karpenter_workload_for_teardown "${TARGET_CLUSTER}" reset
}

confirm_reset
echo ""

teardown_database

case "${PROVISIONING}" in
  eksctl)
    delete_eksctl_nodegroups
    ;;
  karpenter)
    delete_karpenter_workload
    ;;
  *)
    echo "ERROR: unsupported NODE_PROVISIONING: ${PROVISIONING}" >&2
    exit 1
    ;;
esac

echo ""
echo "=== Reset complete ==="
echo "Cluster ${TARGET_CLUSTER} is ready for a fresh start."
echo "Re-bootstrap nodes when ready (see --help)."
