#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd eksctl
require_cmd kubectl
require_cmd aws

KARPENTER_IAM_TEARDOWN="$(dirname "$0")/setup/karpenter/99-teardown-controller-iam.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--main-only | --upgrade-lab-only] [--yes] [--sequential]

Delete EKS training cluster(s).

Default (no flags): delete BOTH clusters in parallel:
  - ${UPGRADE_LAB_CLUSTER_NAME} (upgrade-lab)
  - ${CLUSTER_NAME} (main)

If NODE_PROVISIONING=karpenter, deleting the main cluster also:
  - Drains Karpenter NodePools/NodeClaims first, then sweeps any orphaned
    EC2 instances tagged karpenter.sh/discovery=${CLUSTER_NAME}
  - Removes the raw IAM role/policy from scripts/setup/karpenter/00-install-controller.sh
    (not tracked by eksctl, so cluster deletion alone would leak them)

Options:
  --main-only          Delete main cluster only
  --upgrade-lab-only   Delete upgrade-lab cluster only (after Lab 2.6)
  --yes                Skip confirmation prompt
  --sequential         Delete both clusters one at a time (upgrade-lab, then main)
  -h, --help           Show this help
EOF
}

main_only=false
upgrade_only=false
assume_yes=false
sequential=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main-only) main_only=true ;;
    --upgrade-lab-only) upgrade_only=true ;;
    --yes) assume_yes=true ;;
    --sequential) sequential=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "${main_only}" == true && "${upgrade_only}" == true ]]; then
  echo "ERROR: --main-only and --upgrade-lab-only are mutually exclusive" >&2
  exit 1
fi

clusters=()
if [[ "${upgrade_only}" == true ]]; then
  clusters=("${UPGRADE_LAB_CLUSTER_NAME}")
elif [[ "${main_only}" == true ]]; then
  clusters=("${CLUSTER_NAME}")
else
  clusters=("${UPGRADE_LAB_CLUSTER_NAME}" "${CLUSTER_NAME}")
fi

use_parallel_teardown() {
  [[ "${#clusters[@]}" -gt 1 && "${sequential}" == false ]]
}

print_teardown_plan() {
  echo "=== Teardown plan ==="
  echo "Region: ${AWS_REGION}"
  if use_parallel_teardown; then
    echo "Mode:   parallel delete"
  else
    echo "Mode:   sequential delete"
  fi
  echo ""
  local name
  for name in "${clusters[@]}"; do
    if cluster_exists "${name}"; then
      echo "  DELETE  ${name} (exists)"
    else
      echo "  SKIP    ${name} (not found)"
    fi
  done
}

confirm_teardown() {
  if [[ "${assume_yes}" == true ]]; then
    return 0
  fi
  print_teardown_plan
  echo ""
  read -r -p "Proceed with cluster deletion? [y/N] " reply
  case "${reply}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) echo "Aborted."; exit 0 ;;
  esac
}

# Karpenter is only ever used on the main cluster (upgrade-lab stays on eksctl MNG).
is_karpenter_main_cluster() {
  local name="$1"
  [[ "${NODE_PROVISIONING}" == "karpenter" && "${name}" == "${CLUSTER_NAME}" ]]
}

# Karpenter-launched EC2 instances aren't in any ASG/eksctl-tracked stack, so deleting the
# cluster before they're drained orphans them (they keep running/billing indefinitely).
# Best-effort: delete NodePools/NodeClaims first so Karpenter terminates its own instances.
drain_karpenter_nodepools() {
  local name="$1"
  echo "[delete-${name}] Draining Karpenter NodePools/NodeClaims before cluster deletion..."
  local kc
  kc="$(kubeconfig_path_for_cluster "${name}")"
  if ! aws eks update-kubeconfig --name "${name}" --region "${AWS_REGION}" --kubeconfig "${kc}" >/dev/null 2>&1; then
    echo "[delete-${name}] Could not reach cluster to drain NodePools — skipping (orphan sweep will still run)"
    return 0
  fi
  KUBECONFIG="${kc}" kubectl delete nodepool --all --wait=true --timeout=180s >/dev/null 2>&1 || true
  KUBECONFIG="${kc}" kubectl delete nodeclaim --all --wait=true --timeout=180s >/dev/null 2>&1 || true
}

# Fail-safe for instances that didn't finish draining above (or if the cluster was already
# unreachable): terminate anything still tagged for this cluster by Karpenter's discovery tag.
sweep_orphan_karpenter_instances() {
  local name="$1"
  local orphan_ids
  orphan_ids="$(aws ec2 describe-instances --region "${AWS_REGION}" \
    --filters "Name=tag:karpenter.sh/discovery,Values=${name}" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)"
  if [[ -n "${orphan_ids}" && "${orphan_ids}" != "None" ]]; then
    echo "[delete-${name}] Terminating orphaned Karpenter EC2 instances: ${orphan_ids}"
    aws ec2 terminate-instances --region "${AWS_REGION}" --instance-ids ${orphan_ids} >/dev/null 2>&1 || true
  else
    echo "[delete-${name}] No orphaned Karpenter EC2 instances found"
  fi
}

delete_cluster_async() {
  local name="$1"
  (
    if is_karpenter_main_cluster "${name}"; then
      drain_karpenter_nodepools "${name}"
    fi
    echo "[delete-${name}] Deleting EKS cluster ${name}..."
    eksctl delete cluster --name "${name}" --region "${AWS_REGION}" --wait || exit 1
    echo "[delete-${name}] Deleted ${name}"
    if is_karpenter_main_cluster "${name}"; then
      sweep_orphan_karpenter_instances "${name}"
      if [[ -x "${KARPENTER_IAM_TEARDOWN}" ]]; then
        "${KARPENTER_IAM_TEARDOWN}" || true
      fi
    fi
  )
}

delete_cluster_sequential() {
  local name="$1"
  if ! cluster_exists "${name}"; then
    echo "Skipping ${name} — cluster not found"
    skipped+=("${name}")
    return 0
  fi
  delete_cluster_async "${name}"
  delete_kubecontext_for_cluster "${name}"
  deleted+=("${name}")
}

confirm_teardown
echo ""

deleted=()
skipped=()
to_delete=()
for name in "${clusters[@]}"; do
  if cluster_exists "${name}"; then
    to_delete+=("${name}")
  else
    skipped+=("${name}")
    echo "Skipping ${name} — cluster not found"
  fi
done

if [[ ${#to_delete[@]} -eq 0 ]]; then
  echo "No clusters to delete."
elif use_parallel_teardown; then
  echo "=== Parallel EKS teardown ==="
  pids=()
  for name in "${to_delete[@]}"; do
    delete_cluster_async "${name}" &
    pids+=($!)
  done
  fail=0
  for pid in "${pids[@]}"; do
    wait "${pid}" || fail=1
  done
  if [[ "${fail}" -ne 0 ]]; then
    echo "ERROR: one or more cluster deletions failed" >&2
    exit 1
  fi
  for name in "${to_delete[@]}"; do
    delete_kubecontext_for_cluster "${name}"
    deleted+=("${name}")
  done
  cleanup_workshop_kubeconfig_files
else
  for name in "${to_delete[@]}"; do
    delete_cluster_sequential "${name}"
  done
fi

echo ""
echo "=== Cleanup complete ==="
if [[ ${#deleted[@]} -gt 0 ]]; then
  echo "Deleted: ${deleted[*]}"
fi
if [[ ${#skipped[@]} -gt 0 ]]; then
  echo "Skipped (not found): ${skipped[*]}"
fi
if [[ ${#deleted[@]} -eq 0 ]]; then
  echo "No clusters were deleted."
fi
