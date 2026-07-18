#!/usr/bin/env bash
# Cluster storage selection: disk (default) or dim (in-memory).

: "${CLUSTER_STORAGE:=disk}"
: "${CLUSTER_STORAGE_DIM_LABS:=}"
: "${CLUSTER_STORAGE_DISK_LABS:=}"

lab_id_in_storage_list() {
  local lab_id="$1" list="$2"
  [[ ",${list}," == *",${lab_id},"* ]]
}

resolve_cluster_storage() {
  local lab_id="${1:-}"

  if [[ -n "${CLI_CLUSTER_STORAGE:-}" ]]; then
    echo "${CLI_CLUSTER_STORAGE}"
    return
  fi

  if [[ "${CLUSTER_STORAGE}" == disk ]] \
      && lab_id_in_storage_list "${lab_id}" "${CLUSTER_STORAGE_DIM_LABS}"; then
    echo dim
    return
  fi

  if [[ "${CLUSTER_STORAGE}" == dim ]] \
      && lab_id_in_storage_list "${lab_id}" "${CLUSTER_STORAGE_DISK_LABS}"; then
    echo disk
    return
  fi

  echo "${CLUSTER_STORAGE}"
}

cluster_storage_reason() {
  local lab_id="$1" storage="$2"

  if [[ -n "${CLI_CLUSTER_STORAGE:-}" ]]; then
    echo "CLI override (--${storage})"
    return
  fi

  if [[ "${CLUSTER_STORAGE}" == disk ]] \
      && lab_id_in_storage_list "${lab_id}" "${CLUSTER_STORAGE_DIM_LABS}"; then
    echo "lab ${lab_id} listed in CLUSTER_STORAGE_DIM_LABS"
    return
  fi

  if [[ "${CLUSTER_STORAGE}" == dim ]] \
      && lab_id_in_storage_list "${lab_id}" "${CLUSTER_STORAGE_DISK_LABS}"; then
    echo "lab ${lab_id} listed in CLUSTER_STORAGE_DISK_LABS"
    return
  fi

  echo "CLUSTER_STORAGE=${CLUSTER_STORAGE}"
}

log_cluster_storage_choice() {
  local lab_id="$1"
  local storage reason
  storage="$(resolve_cluster_storage "${lab_id}")"
  reason="$(cluster_storage_reason "${lab_id}" "${storage}")"
  echo "Using cluster storage: ${storage} (${reason})"
  export EFFECTIVE_CLUSTER_STORAGE="${storage}"
}

disk_manifest_basename() {
  local base="$1"
  case "${base}" in
    dim-cluster*) echo "disk-${base#dim-}" ;;
    upgrade-lab-dim-cluster) echo "upgrade-lab-disk-cluster" ;;
    *) echo "disk-${base}" ;;
  esac
}

disk_helm_basename() {
  local base="$1"
  case "${base}" in
    dim-cluster*) echo "disk-${base#dim-}-values" ;;
    upgrade-lab-dim-cluster) echo "upgrade-lab-disk-cluster-values" ;;
    *) echo "disk-${base}-values" ;;
  esac
}

resolve_cluster_manifest() {
  local base="$1" storage="${2:-${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}}}"
  if [[ "${storage}" == dim ]]; then
    echo "${WORKSHOP_ROOT}/manifests/${base}.yaml"
  else
    echo "${WORKSHOP_ROOT}/manifests/$(disk_manifest_basename "${base}").yaml"
  fi
}

resolve_cluster_helm_values() {
  local base="$1" storage="${2:-${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}}}"
  if [[ "${storage}" == dim ]]; then
    case "${base}" in
      dim-cluster*) echo "${WORKSHOP_ROOT}/helm/${base}-values.yaml" ;;
      upgrade-lab-dim-cluster) echo "${WORKSHOP_ROOT}/helm/upgrade-lab-dim-cluster-values.yaml" ;;
      aerospike-upgrade) echo "${WORKSHOP_ROOT}/helm/aerospike-upgrade-values.yaml" ;;
      pod-restart-op) echo "${WORKSHOP_ROOT}/helm/pod-restart-op-values.yaml" ;;
      pod-warm-restart-op) echo "${WORKSHOP_ROOT}/helm/pod-warm-restart-op-values.yaml" ;;
      node-blocklist) echo "${WORKSHOP_ROOT}/helm/node-blocklist-values.yaml" ;;
      replication-factor-rf3) echo "${WORKSHOP_ROOT}/helm/replication-factor-rf3-values.yaml" ;;
      *) echo "${WORKSHOP_ROOT}/helm/${base}-values.yaml" ;;
    esac
  else
    echo "${WORKSHOP_ROOT}/helm/$(disk_helm_basename "${base}").yaml"
  fi
}

cluster_storage_engine_type() {
  kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster \
    -o jsonpath='{.spec.aerospikeConfig.namespaces[0].storage-engine.type}' 2>/dev/null || echo missing
}

validate_cluster_storage_engine() {
  local expected="$1"
  local actual
  actual="$(cluster_storage_engine_type)"
  if [[ "${actual}" == "${expected}" ]]; then
    echo "OK  storage-engine type ${actual}"
    return 0
  fi
  echo "FAIL expected storage-engine ${expected} (got ${actual})" >&2
  return 1
}

validate_baseline_local_ssd_pvs() {
  local expected_pods="${1:-3}"
  source "$(dirname "${BASH_SOURCE[0]}")/local-storage.sh"
  ensure_local_ssd_pvs_for_pool "${NODE_TYPE}" "${expected_pods}" "baseline (${NODE_TYPE})"
}

wait_for_cluster_gone() {
  local timeout="${1:-300}"
  local deadline=$((SECONDS + timeout))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    if ! kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
      local remaining
      remaining="$(kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster --no-headers 2>/dev/null | wc -l | tr -d ' ')"
      if [[ "${remaining:-0}" -eq 0 ]]; then
        echo "OK  aerocluster removed"
        return 0
      fi
    fi
    sleep 5
  done
  echo "ERROR: aerocluster or pods still present after teardown" >&2
  kubectl -n "${NAMESPACE}" get aerospikecluster,pods 2>/dev/null || true
  return 1
}
