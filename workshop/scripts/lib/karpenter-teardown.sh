#!/usr/bin/env bash
# Shared Karpenter workload teardown (NodePools, bootstrap, orphan EC2 sweep).
# Requires load_env() and nodepool-zones.sh. Karpenter main-cluster path only.
set -euo pipefail

: "${KARPENTER_DRAIN_TIMEOUT:=900}"
: "${KARPENTER_AEROSPIKE_TEARDOWN_TIMEOUT:=120}"
: "${KARPENTER_TEARDOWN_LOG_PREFIX:=}"

_karpenter_teardown_log() {
  echo "${KARPENTER_TEARDOWN_LOG_PREFIX}$*"
}

assert_karpenter_provisioning() {
  [[ "${NODE_PROVISIONING}" == "karpenter" ]] && return 0
  echo "ERROR: karpenter-teardown requires NODE_PROVISIONING=karpenter (got: ${NODE_PROVISIONING})" >&2
  return 1
}

delete_karpenter_bootstrap_deployments() {
  assert_karpenter_provisioning

  local prefix zone dep_name
  _delete_bootstrap_deployments_by_name() {
    prefix="$1"
    read_aws_zones_array
    for zone in "${AWS_ZONES_ARRAY[@]}"; do
      [[ -z "${zone}" ]] && continue
      dep_name="${prefix}-$(zone_resource_suffix "${zone}")"
      _karpenter_teardown_log "  Deleting Deployment ${dep_name}..."
      kubectl delete deployment "${dep_name}" -n kube-system --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
    done
  }

  _karpenter_teardown_log "Deleting bootstrap Deployments..."
  _delete_bootstrap_deployments_by_name "karpenter-bootstrap"
  _delete_bootstrap_deployments_by_name "karpenter-vertical-bootstrap"

  kubectl delete pod -n kube-system -l app=karpenter-bootstrap --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
  kubectl delete pod -n kube-system -l app=karpenter-vertical-bootstrap --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
}

delete_karpenter_workload_pools() {
  assert_karpenter_provisioning

  local pool
  _karpenter_teardown_log "Deleting NodeClaims..."
  kubectl delete nodeclaim --all --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

  while IFS= read -r pool; do
    [[ -z "${pool}" ]] && continue
    if kubectl get nodepool "${pool}" >/dev/null 2>&1; then
      _karpenter_teardown_log "Deleting NodePool ${pool}..."
      kubectl delete nodepool "${pool}" --wait=true --timeout=180s 2>/dev/null || true
    fi
  done < <(list_vertical_pool_names; list_baseline_pool_names)
}

wait_for_karpenter_workload_nodes_gone() {
  local timeout_secs="${1:-${KARPENTER_DRAIN_TIMEOUT}}"
  local deadline=$((SECONDS + timeout_secs))

  _karpenter_teardown_log "Waiting for Karpenter workload nodes to terminate (timeout ${timeout_secs}s)..."
  while true; do
    local workload_nodes
    workload_nodes="$(kubectl get nodes -l 'workshop.aerospike.com/workload=aerospike' --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${workload_nodes}" -eq 0 ]]; then
      _karpenter_teardown_log "Karpenter workload nodes removed."
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      _karpenter_teardown_log "WARN timed out waiting for workload nodes (${workload_nodes} remaining)"
      kubectl get nodes -L workshop.aerospike.com/workload -o wide 2>/dev/null || true
      return 1
    fi
    _karpenter_teardown_log "  ${workload_nodes} workload node(s) still present..."
    sleep 15
  done
}

sweep_orphan_karpenter_instances() {
  local cluster_name="$1"
  local orphan_ids
  orphan_ids="$(aws ec2 describe-instances --region "${AWS_REGION}" \
    --filters "Name=tag:karpenter.sh/discovery,Values=${cluster_name}" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)"
  if [[ -n "${orphan_ids}" && "${orphan_ids}" != "None" ]]; then
    _karpenter_teardown_log "Terminating orphaned Karpenter EC2 instances: ${orphan_ids}"
    # shellcheck disable=SC2086
    aws ec2 terminate-instances --region "${AWS_REGION}" --instance-ids ${orphan_ids} >/dev/null 2>&1 || true
  else
    _karpenter_teardown_log "No orphaned Karpenter EC2 instances found"
  fi
}

teardown_aerospike_workloads_best_effort() {
  if [[ "${DEPLOY_PATH}" == "helm" ]]; then
    _karpenter_teardown_log "Uninstalling Helm release ${HELM_CLUSTER_RELEASE} (best-effort)..."
    helm uninstall "${HELM_CLUSTER_RELEASE}" -n "${NAMESPACE}" 2>/dev/null || true
  else
    _karpenter_teardown_log "Deleting AerospikeCluster CRs (best-effort)..."
    kubectl delete aerospikecluster aerocluster -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true
  fi
  kubectl delete aerospikecluster local-ssd-demo -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true

  local deadline=$((SECONDS + KARPENTER_AEROSPIKE_TEARDOWN_TIMEOUT))
  while true; do
    local remaining
    remaining="$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null \
      | awk '$1 ~ /^aerocluster/ || $1 ~ /^local-ssd-demo/' | wc -l | tr -d ' ')"
    if [[ "${remaining}" -eq 0 ]]; then
      break
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      _karpenter_teardown_log "WARN timed out waiting for Aerospike pods (${remaining} remaining) — continuing"
      break
    fi
    _karpenter_teardown_log "  ${remaining} Aerospike pod(s) still terminating..."
    sleep 10
  done
}

# Quick pool reset: bootstrap + NodeClaims + NodePools (no node wait). Used by 01-reset-workload-nodepools.sh.
reset_karpenter_workload_pools_quick() {
  assert_karpenter_provisioning
  delete_karpenter_bootstrap_deployments
  delete_karpenter_workload_pools
}

# mode=reset — fail on node wait timeout. mode=delete — best-effort + pre-delete orphan sweep on timeout.
drain_karpenter_workload_for_teardown() {
  local cluster_name="$1"
  local mode="${2:-delete}"
  assert_karpenter_provisioning

  _karpenter_teardown_log "Draining Karpenter workload pools..."
  delete_karpenter_bootstrap_deployments
  delete_karpenter_workload_pools

  if wait_for_karpenter_workload_nodes_gone "${KARPENTER_DRAIN_TIMEOUT}"; then
    return 0
  fi

  case "${mode}" in
    reset)
      echo "ERROR: timed out waiting for Karpenter workload nodes to terminate on ${cluster_name}" >&2
      exit 1
      ;;
    delete)
      _karpenter_teardown_log "Running pre-delete orphan EC2 sweep..."
      sweep_orphan_karpenter_instances "${cluster_name}"
      return 0
      ;;
    *)
      echo "ERROR: drain_karpenter_workload_for_teardown mode must be reset or delete (got: ${mode})" >&2
      return 1
      ;;
  esac
}
