#!/usr/bin/env bash
# testing/lib/wait-helpers.sh
#
# Generic, timeout-bound poll/assert helpers shared by testing/labs/*.sh.
# These replace every interactive/manual guide step (kubectl get -w, asadm
# interactive prompts, human "watch until it looks done") with scripted,
# non-interactive equivalents.
#
# Expects testing/lib/lab-env.sh to have already sourced workshop/scripts/lib/
# common.sh + cluster-storage.sh and run load_env / ensure_main_kubecontext,
# so NAMESPACE, CLUSTER_NAME, DEPLOY_PATH, HELM_REPO, HELM_CLUSTER_RELEASE,
# AKO_VERSION_START, etc. are already exported.

: "${TEST_POLL_INTERVAL:=15}"

log_info() { echo "INFO  $*"; }
log_pass() { echo "PASS  $*"; }
log_warn() { echo "WARN  $*" >&2; }
log_fail() { echo "FAIL  $*" >&2; }

fail_lab() {
  log_fail "$*"
  exit 1
}

# ---- Aerospike CR / pod polling -------------------------------------------

cr_phase() {
  kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.status.phase}' 2>/dev/null || echo unknown
}

cr_image() {
  kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.spec.image}' 2>/dev/null || echo unknown
}

cr_replication_factor() {
  kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster \
    -o jsonpath='{.spec.aerospikeConfig.namespaces[0].replication-factor}' 2>/dev/null || echo unknown
}

wait_pods_running() {
  local label="$1" count="$2" timeout="${3:-600}"
  local deadline=$((SECONDS + timeout))
  while true; do
    local running
    running="$(kubectl -n "${NAMESPACE}" get pods -l "${label}" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${running:-0}" -ge "${count}" ]]; then
      log_pass "${running}/${count} pods Running (label ${label})"
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      log_fail "timed out waiting for ${count} Running pods (label ${label}); currently ${running:-0}"
      kubectl -n "${NAMESPACE}" get pods -l "${label}" -o wide 2>/dev/null || true
      return 1
    fi
    sleep "${TEST_POLL_INTERVAL}"
  done
}

wait_cr_phase() {
  local phase="${1:-Completed}" timeout="${2:-600}"
  log_info "Waiting for aerocluster phase=${phase} (timeout ${timeout}s)..."
  if kubectl -n "${NAMESPACE}" wait --for=jsonpath='{.status.phase}'="${phase}" \
      aerospikecluster/aerocluster --timeout="${timeout}s" >/dev/null 2>&1; then
    log_pass "aerocluster phase=${phase}"
    return 0
  fi
  log_fail "aerocluster did not reach phase=${phase} within ${timeout}s (current: $(cr_phase))"
  kubectl -n "${NAMESPACE}" get aerospikecluster,pods 2>/dev/null || true
  return 1
}

wait_rack_replacement_settled() {
  local expected_count="$1" old_rack_pattern="$2" timeout="${3:-1200}"
  local deadline=$((SECONDS + timeout))
  while true; do
    local names count old_present phase
    names="$(kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
    count="$(echo "${names}" | tr ' ' '\n' | grep -c . || true)"
    old_present="$(echo "${names}" | tr ' ' '\n' | grep -E "${old_rack_pattern}" || true)"
    phase="$(cr_phase)"
    if [[ "${count}" -eq "${expected_count}" && -z "${old_present}" && "${phase}" == "Completed" ]]; then
      log_pass "rack replacement settled: ${count} pods, no pods matching '${old_rack_pattern}', phase Completed"
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      log_fail "timed out waiting for rack replacement to settle (count=${count} phase=${phase})"
      kubectl -n "${NAMESPACE}" get pods -o wide 2>/dev/null || true
      return 1
    fi
    sleep "${TEST_POLL_INTERVAL}"
  done
}

# ---- Node polling -----------------------------------------------------------

wait_nodes_ready() {
  local label="$1" count="$2" timeout="${3:-900}"
  local deadline=$((SECONDS + timeout))
  while true; do
    local ready
    ready="$(kubectl get nodes -l "${label}" --no-headers 2>/dev/null | grep -c ' Ready ' || true)"
    if [[ "${ready:-0}" -ge "${count}" ]]; then
      log_pass "${ready}/${count} nodes Ready (label ${label})"
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      log_fail "timed out waiting for ${count} Ready nodes (label ${label}); currently ${ready:-0}"
      return 1
    fi
    sleep "${TEST_POLL_INTERVAL}"
  done
}

wait_node_gone() {
  local node="$1" timeout="${2:-300}"
  local deadline=$((SECONDS + timeout))
  while kubectl get node "${node}" >/dev/null 2>&1; do
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      log_fail "timed out waiting for node ${node} to be removed"
      return 1
    fi
    sleep "${TEST_POLL_INTERVAL}"
  done
  log_pass "node ${node} removed"
  return 0
}

wait_pod_moved_off_node() {
  local pod="$1" old_node="$2" timeout="${3:-900}"
  local deadline=$((SECONDS + timeout))
  while true; do
    local current_node phase
    current_node="$(kubectl -n "${NAMESPACE}" get pod "${pod}" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)"
    phase="$(kubectl -n "${NAMESPACE}" get pod "${pod}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ -n "${current_node}" && "${current_node}" != "${old_node}" && "${phase}" == "Running" ]]; then
      log_pass "${pod} Running on new node ${current_node} (was ${old_node})"
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      log_fail "timed out waiting for ${pod} to reschedule off ${old_node} (still: node=${current_node:-none} phase=${phase:-unknown})"
      return 1
    fi
    sleep "${TEST_POLL_INTERVAL}"
  done
}

# Best-effort, non-fatal: orphaned local-ssd PVC cleanup lags node termination
# by design (~60s cleanup-controller delay) — callers should WARN, not fail_lab.
wait_pvc_cleanup() {
  local node="$1" timeout="${2:-180}"
  local deadline=$((SECONDS + timeout))
  while true; do
    local count
    count="$(kubectl -n "${NAMESPACE}" get pvc -o json 2>/dev/null | grep -c "\"${node}\"" || true)"
    if [[ "${count:-0}" -eq 0 ]]; then
      log_pass "no PVCs referencing node ${node} (cleanup complete)"
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      log_warn "PVC cleanup for node ${node} not confirmed within ${timeout}s (non-fatal; pod reschedule is the authoritative signal)"
      return 1
    fi
    sleep 10
  done
}

# ---- asadm / pod exec (non-interactive) ------------------------------------

run_asadm() {
  local cmd="$1"
  local user="${2:-${AEROSPIKE_AUTH_USER:-admin}}"
  local pass="${3:-${AEROSPIKE_AUTH_PASSWORD:-admin123}}"
  kubectl run "asadm-test-$$-${RANDOM}" -n "${NAMESPACE}" --restart=Never --rm -i \
    --image=aerospike/aerospike-tools:latest -- \
    asadm -h aerocluster -U "${user}" -P "${pass}" -e "${cmd}" 2>/dev/null || true
}

pod_exec() {
  local pod="$1"; shift
  kubectl -n "${NAMESPACE}" exec "${pod}" -c aerospike-server -- "$@" 2>/dev/null || true
}

first_pod_matching() {
  local pattern="$1"
  kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster -o jsonpath='{.items[*].metadata.name}' 2>/dev/null \
    | tr ' ' '\n' | grep "${pattern}" | head -1
}

pod_node() {
  kubectl -n "${NAMESPACE}" get pod "$1" -o jsonpath='{.spec.nodeName}' 2>/dev/null
}

pod_field() {
  kubectl -n "${NAMESPACE}" get pod "$1" -o jsonpath="$2" 2>/dev/null
}

count_bound_local_ssd_pvcs() {
  kubectl -n "${NAMESPACE}" get pvc -o custom-columns=STATUS:.status.phase,CLASS:.spec.storageClassName --no-headers 2>/dev/null \
    | awk '$1=="Bound" && $2=="local-ssd" {c++} END{print c+0}'
}

# ---- Snapshot / diff assertions --------------------------------------------

snapshot_pods() {
  local label="${1:-aerospike.com/cr=aerocluster}"
  kubectl -n "${NAMESPACE}" get pods -l "${label}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.uid}{" "}{.status.startTime}{" "}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null | sort
}

assert_pods_unchanged() {
  local before="$1" after="$2" context="${3:-pods}"
  if [[ "${before}" == "${after}" ]]; then
    log_pass "${context}: pod identity/startTime/restartCount unchanged (no rolling restart)"
    return 0
  fi
  log_fail "${context}: pod state changed unexpectedly"
  diff <(echo "${before}") <(echo "${after}") || true
  return 1
}

assert_pods_changed() {
  local before="$1" after="$2" context="${3:-pods}"
  if [[ "${before}" != "${after}" ]]; then
    log_pass "${context}: pod state changed as expected (restart occurred)"
    return 0
  fi
  log_fail "${context}: expected pod state to change but it did not"
  return 1
}

# ---- Generic assertions -----------------------------------------------------

assert_eq() {
  local actual="$1" expected="$2" desc="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    log_pass "${desc}: ${actual}"
    return 0
  fi
  log_fail "${desc}: expected '${expected}', got '${actual}'"
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    log_pass "${desc}: contains '${needle}'"
    return 0
  fi
  log_fail "${desc}: expected to contain '${needle}', got '${haystack}'"
  return 1
}

assert_not_empty() {
  local value="$1" desc="$2"
  if [[ -n "${value}" ]]; then
    log_pass "${desc}: non-empty (${value})"
    return 0
  fi
  log_fail "${desc}: expected non-empty value"
  return 1
}

assert_no_pods_matching() {
  local pattern="$1" desc="$2"
  local matches
  matches="$(kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "${pattern}" || true)"
  if [[ -z "${matches}" ]]; then
    log_pass "${desc}: no pods matching '${pattern}'"
    return 0
  fi
  log_fail "${desc}: found unexpected pods matching '${pattern}': ${matches}"
  return 1
}

# ---- Cluster apply helpers (DEPLOY_PATH dispatch) --------------------------
# These wrap resolve_cluster_manifest / resolve_cluster_helm_values (from
# workshop/scripts/lib/cluster-storage.sh) so testing/labs/*.sh can apply a
# manifest "base name" without duplicating DEPLOY_PATH branching everywhere.

ensure_helm_repo() {
  require_cmd helm
  helm repo add aerospike "${HELM_REPO}" >/dev/null 2>&1 || true
  helm repo update >/dev/null
}

apply_cluster_manifest() {
  local base="$1"
  local manifest
  manifest="$(resolve_cluster_manifest "${base}")"
  log_info "kubectl apply -f ${manifest}"
  kubectl apply -f "${manifest}"
}

helm_upgrade_cluster_values() {
  local base="$1" version="${2:-${AKO_VERSION_START}}"
  local values
  values="$(resolve_cluster_helm_values "${base}")"
  ensure_helm_repo
  log_info "helm upgrade ${HELM_CLUSTER_RELEASE} aerospike/aerospike-cluster -f ${values} --version=${version}"
  helm upgrade --install "${HELM_CLUSTER_RELEASE}" aerospike/aerospike-cluster \
    --namespace "${NAMESPACE}" --create-namespace \
    --version="${version}" \
    -f "${values}"
}

# Dispatches on DEPLOY_PATH; base is the resolve_cluster_manifest /
# resolve_cluster_helm_values base name (e.g. dim-cluster, dim-cluster-scale-5).
apply_cluster_change() {
  local base="$1" version="${2:-${AKO_VERSION_START}}"
  if [[ "${DEPLOY_PATH}" == "helm" ]]; then
    helm_upgrade_cluster_values "${base}" "${version}"
  else
    apply_cluster_manifest "${base}"
  fi
}
