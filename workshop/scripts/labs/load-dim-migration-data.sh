#!/usr/bin/env bash
# Load records into the dim cluster so node-drain migration is visible (Lab 2.5).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl

: "${MIGRATION_LOAD_NAMESPACE:=test}"
: "${MIGRATION_LOAD_RECORDS:=5000000}"
: "${MIGRATION_LOAD_OBJECT_SIZE:=1024}"
: "${MIGRATION_LOAD_THREADS:=4}"
: "${MIGRATION_LOAD_DURATION:=0}"
: "${AEROSPIKE_AUTH_USER:=app}"
: "${AEROSPIKE_AUTH_PASSWORD:=app123}"

validate_cluster_ready() {
  local phase running expected=3
  phase="$(kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.status.phase}' 2>/dev/null || echo missing)"
  running="$(kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"

  if [[ "${phase}" == "Completed" ]] && [[ "${running:-0}" -ge "${expected}" ]]; then
    echo "OK  cluster Ready (${running}/${expected} pods, phase ${phase})"
    return 0
  fi

  echo "ERROR: cluster not ready (phase=${phase}, ${running}/${expected} pods Running)" >&2
  kubectl -n "${NAMESPACE}" get aerospikecluster,pods 2>/dev/null || true
  exit 1
}

print_namespace_stats() {
  echo "=== Namespace ${MIGRATION_LOAD_NAMESPACE} stats ==="
  kubectl run "aerospike-tool-stats-$$" -n "${NAMESPACE}" --restart=Never \
    --image=aerospike/aerospike-tools:latest --rm -i -- \
    asinfo -h aerocluster -U "${AEROSPIKE_AUTH_USER}" -P "${AEROSPIKE_AUTH_PASSWORD}" \
    -v "namespace/${MIGRATION_LOAD_NAMESPACE}" 2>/dev/null || true
}

echo "=== Load dim migration data (Lab 2.5) ==="
validate_cluster_ready

echo "Loading ${MIGRATION_LOAD_RECORDS} records (~${MIGRATION_LOAD_OBJECT_SIZE} bytes each) into namespace ${MIGRATION_LOAD_NAMESPACE}..."

asbench_args=(
  -h aerocluster
  -U "${AEROSPIKE_AUTH_USER}"
  -P "${AEROSPIKE_AUTH_PASSWORD}"
  -n "${MIGRATION_LOAD_NAMESPACE}"
  -k "${MIGRATION_LOAD_RECORDS}"
  -o "S${MIGRATION_LOAD_OBJECT_SIZE}"
  -w I
  -g "${MIGRATION_LOAD_THREADS}"
  -z "${MIGRATION_LOAD_THREADS}"
)

if [[ "${MIGRATION_LOAD_DURATION}" -gt 0 ]]; then
  asbench_args+=(-T "${MIGRATION_LOAD_DURATION}")
fi

kubectl run "asbench-load-$$" -n "${NAMESPACE}" --restart=Never \
  --image=aerospike/aerospike-tools:latest --rm -i -- \
  asbench "${asbench_args[@]}"

print_namespace_stats
echo "=== Data load complete — proceed with drain demo ==="
