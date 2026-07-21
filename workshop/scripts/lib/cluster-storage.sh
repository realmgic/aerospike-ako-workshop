#!/usr/bin/env bash
# Cluster storage selection: disk (default) or dim (in-memory).

if [[ -n "${BASH_VERSION:-}" ]]; then
  _LIB_SELF="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  _LIB_SELF="${(%):-%x}"
else
  _LIB_SELF="$0"
fi
SCRIPT_DIR="$(cd "$(dirname "${_LIB_SELF}")" && pwd)"
unset _LIB_SELF

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
    dim-cluster|upgrade-lab-dim-cluster) echo "disk-cluster" ;;
    dim-cluster*) echo "disk-${base#dim-}" ;;
    *) echo "disk-${base}" ;;
  esac
}

disk_helm_basename() {
  local base="$1"
  case "${base}" in
    dim-cluster) echo "disk-cluster-values" ;;
    dim-cluster*) echo "disk-${base#dim-}-values" ;;
    upgrade-lab-dim-cluster) echo "disk-cluster-values" ;;
    *) echo "disk-${base}-values" ;;
  esac
}

cluster_helm_base_path() {
  local storage="$1"
  if [[ "${storage}" == dim ]]; then
    echo "${WORKSHOP_ROOT}/helm/base-dim-cluster-values.yaml"
  else
    echo "${WORKSHOP_ROOT}/helm/base-disk-cluster-values.yaml"
  fi
}

cluster_helm_overlay_path() {
  local storage="$1" name="$2"
  case "${name}" in
    replication-factor-rf3|cluster-tls-standard|cluster-tls-mtls|cluster-tls-mtls-pki-only|cluster-tls-mtls-blacklist)
      if [[ "${storage}" == dim ]]; then
        echo "${WORKSHOP_ROOT}/helm/overlay-dim-${name}-values.yaml"
      else
        echo "${WORKSHOP_ROOT}/helm/overlay-disk-${name}-values.yaml"
      fi
      ;;
    *)
      echo "${WORKSHOP_ROOT}/helm/overlay-${name}-values.yaml"
      ;;
  esac
}

resolve_cluster_helm_value_files() {
  local base="$1" storage="${2:-${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}}}"
  case "${base}" in
    dim-cluster|upgrade-lab-dim-cluster)
      cluster_helm_base_path "${storage}"
      ;;
    dim-cluster-maintenance)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "cluster-maintenance"
      ;;
    dim-cluster-scale-5)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "cluster-scale-5"
      ;;
    replication-factor-rf3)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "replication-factor-rf3"
      ;;
    pod-warm-restart-op)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "pod-warm-restart-op"
      ;;
    pod-restart-op)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "pod-restart-op"
      ;;
    aerospike-upgrade)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "aerospike-upgrade"
      ;;
    node-blocklist)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "cluster-maintenance"
      cluster_helm_overlay_path "${storage}" "node-blocklist"
      ;;
    dim-cluster-tls-standard)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "cluster-tls-standard"
      ;;
    dim-cluster-tls-mtls)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "cluster-tls-mtls"
      ;;
    dim-cluster-tls-mtls-pki-only)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "cluster-tls-mtls-pki-only"
      ;;
    dim-cluster-tls-mtls-blacklist)
      cluster_helm_base_path "${storage}"
      cluster_helm_overlay_path "${storage}" "cluster-tls-mtls-blacklist"
      ;;
    *)
      if [[ "${storage}" == dim ]]; then
        echo "${WORKSHOP_ROOT}/helm/${base}-values.yaml"
      else
        echo "${WORKSHOP_ROOT}/helm/$(disk_helm_basename "${base}").yaml"
      fi
      ;;
  esac
}

resolve_cluster_manifest() {
  local base="$1" storage="${2:-${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}}}"
  if [[ "${storage}" == dim ]]; then
    case "${base}" in
      replication-factor-rf3) echo "${WORKSHOP_ROOT}/manifests/dim-replication-factor-rf3.yaml" ;;
      upgrade-lab-dim-cluster|dim-cluster) echo "${WORKSHOP_ROOT}/manifests/dim-cluster.yaml" ;;
      dim-cluster*) echo "${WORKSHOP_ROOT}/manifests/${base}.yaml" ;;
      *) echo "${WORKSHOP_ROOT}/manifests/${base}.yaml" ;;
    esac
  else
    echo "${WORKSHOP_ROOT}/manifests/$(disk_manifest_basename "${base}").yaml"
  fi
}

resolve_cluster_helm_values() {
  resolve_cluster_helm_value_files "$@" | head -n1
}

build_cluster_helm_value_args() {
  local base="$1" storage="${2:-${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}}}"
  local f
  CLUSTER_HELM_VALUE_FILES=()
  CLUSTER_HELM_VALUE_ARGS=()
  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    CLUSTER_HELM_VALUE_FILES+=("${f}")
    CLUSTER_HELM_VALUE_ARGS+=(-f "${f}")
  done < <(resolve_cluster_helm_value_files "${base}" "${storage}")
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
  source "${SCRIPT_DIR}/local-storage.sh"
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
