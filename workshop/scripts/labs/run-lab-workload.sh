#!/usr/bin/env bash
# Continuous read/update workload for availability demos (Labs 2.3, 2.4, 2.6).
#
# Usage:
#   ./scripts/labs/run-lab-workload.sh start|stop|status
#   ./scripts/labs/run-lab-workload.sh --upgrade-lab start   # Lab 2.6 upgrade-lab cluster
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
require_cmd kubectl

WORKLOAD_JOB_NAME="workshop-asbench-workload"
: "${WORKLOAD_NAMESPACE:=test}"
: "${WORKLOAD_RECORDS:=5000000}"
: "${WORKLOAD_OBJECT_SIZE:=1024}"
: "${WORKLOAD_TPS:=10000}"
: "${WORKLOAD_THREADS:=64}"
: "${WORKLOAD_DURATION:=86400}"
: "${AEROSPIKE_AUTH_USER:=app}"
: "${AEROSPIKE_AUTH_PASSWORD:=app123}"

UPGRADE_LAB=false
ACTION=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [--upgrade-lab] start|stop|status

Run continuous asbench read/update (RU,50 at ${WORKLOAD_TPS} TPS) in a background Job.
Use a second terminal window — watch debug output with 'status'.

  start   Create Job ${WORKLOAD_JOB_NAME}
  stop    Delete Job ${WORKLOAD_JOB_NAME}
  status  Show Job state and tail logs

  --upgrade-lab   Target Lab 2.6 upgrade-lab cluster (default: main cluster)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upgrade-lab) UPGRADE_LAB=true ;;
    start|stop|status)
      if [[ -n "${ACTION}" ]]; then
        echo "ERROR: specify one action: start, stop, or status" >&2
        exit 1
      fi
      ACTION="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

[[ -n "${ACTION}" ]] || { usage >&2; exit 1; }

ensure_target_kubecontext() {
  if [[ "${UPGRADE_LAB}" == true ]]; then
    ensure_upgrade_lab_kubecontext
  else
    ensure_main_kubecontext
  fi
}

validate_cluster_exists() {
  if kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
    echo "OK  AerospikeCluster aerocluster exists"
    return 0
  fi
  echo "ERROR: AerospikeCluster aerocluster not found in namespace ${NAMESPACE}" >&2
  exit 1
}

workload_pod_name() {
  kubectl -n "${NAMESPACE}" get pods -l "job-name=${WORKLOAD_JOB_NAME}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

start_workload() {
  validate_cluster_exists

  if kubectl -n "${NAMESPACE}" get job "${WORKLOAD_JOB_NAME}" >/dev/null 2>&1; then
    echo "ERROR: Job ${WORKLOAD_JOB_NAME} already exists — run 'stop' first" >&2
    exit 1
  fi

  echo "=== Starting workload Job (${WORKLOAD_TPS} TPS, RU,50) ==="

  kubectl -n "${NAMESPACE}" create job "${WORKLOAD_JOB_NAME}" \
    --image=aerospike/aerospike-tools:latest \
    -- asbench \
      -h aerocluster \
      -U "${AEROSPIKE_AUTH_USER}" \
      -P "${AEROSPIKE_AUTH_PASSWORD}" \
      -n "${WORKLOAD_NAMESPACE}" \
      -k "${WORKLOAD_RECORDS}" \
      -o "S${WORKLOAD_OBJECT_SIZE}" \
      -w "RU,50" \
      -g "${WORKLOAD_TPS}" \
      -z "${WORKLOAD_THREADS}" \
      -t "${WORKLOAD_DURATION}" \
      --debug

  echo "Job ${WORKLOAD_JOB_NAME} created. Watch from this terminal:"
  upgrade_lab_flag=""
  [[ "${UPGRADE_LAB}" == true ]] && upgrade_lab_flag=" --upgrade-lab"
  echo "  ./scripts/labs/run-lab-workload.sh${upgrade_lab_flag} status"
}

stop_workload() {
  if kubectl -n "${NAMESPACE}" delete job "${WORKLOAD_JOB_NAME}" --ignore-not-found; then
    echo "=== Workload stopped ==="
  fi
}

status_workload() {
  if ! kubectl -n "${NAMESPACE}" get job "${WORKLOAD_JOB_NAME}" >/dev/null 2>&1; then
    echo "No workload Job (${WORKLOAD_JOB_NAME}) running."
    exit 1
  fi

  kubectl -n "${NAMESPACE}" get job "${WORKLOAD_JOB_NAME}"
  local pod
  pod="$(workload_pod_name)"
  if [[ -z "${pod}" ]]; then
    echo "Waiting for workload pod..."
    local deadline=$((SECONDS + 120))
    while [[ "${SECONDS}" -lt "${deadline}" ]]; do
      pod="$(workload_pod_name)"
      [[ -n "${pod}" ]] && break
      sleep 2
    done
  fi

  if [[ -n "${pod}" ]]; then
    echo "=== Logs (${pod}) ==="
    kubectl -n "${NAMESPACE}" logs -f "${pod}" --tail=50
  else
    kubectl -n "${NAMESPACE}" get pods -l "job-name=${WORKLOAD_JOB_NAME}"
  fi
}

ensure_target_kubecontext

case "${ACTION}" in
  start) start_workload ;;
  stop) stop_workload ;;
  status) status_workload ;;
esac
