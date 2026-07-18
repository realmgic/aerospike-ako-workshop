#!/usr/bin/env bash
# Load records into the cluster (5M x 1KB insert via asbench).
#
# Usage:
#   ./scripts/labs/load-data.sh
#   ./scripts/labs/load-data.sh --upgrade-lab   # Lab 2.6 upgrade-lab cluster
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
require_cmd kubectl

UPGRADE_LAB=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upgrade-lab) UPGRADE_LAB=true ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--upgrade-lab]

Load records into the Aerospike cluster via asbench insert.

  --upgrade-lab   Target Lab 2.6 upgrade-lab cluster (default: main cluster)
EOF
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

: "${MIGRATION_LOAD_NAMESPACE:=test}"
: "${MIGRATION_LOAD_RECORDS:=5000000}"
: "${MIGRATION_LOAD_OBJECT_SIZE:=1024}"
: "${MIGRATION_LOAD_THREADS:=64}"
: "${MIGRATION_LOAD_DURATION:=0}"
: "${AEROSPIKE_AUTH_USER:=app}"
: "${AEROSPIKE_AUTH_PASSWORD:=app123}"

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

print_namespace_stats() {
  echo "=== Namespace ${MIGRATION_LOAD_NAMESPACE} stats ==="
  kubectl run "aerospike-tool-stats-$$" -n "${NAMESPACE}" --restart=Never \
    --image=aerospike/aerospike-tools:latest --rm -i -- \
    asadm -h aerocluster -U "${AEROSPIKE_AUTH_USER}" -P "${AEROSPIKE_AUTH_PASSWORD}" \
    -e "info" 2>/dev/null || true
}

ensure_target_kubecontext

echo "=== Load data ==="
validate_cluster_exists

echo "Loading ${MIGRATION_LOAD_RECORDS} records (~${MIGRATION_LOAD_OBJECT_SIZE} bytes each) into namespace ${MIGRATION_LOAD_NAMESPACE}..."

asbench_args=(
  -h aerocluster
  -U "${AEROSPIKE_AUTH_USER}"
  -P "${AEROSPIKE_AUTH_PASSWORD}"
  -n "${MIGRATION_LOAD_NAMESPACE}"
  -k "${MIGRATION_LOAD_RECORDS}"
  -o "S${MIGRATION_LOAD_OBJECT_SIZE}"
  -w I
  -z "${MIGRATION_LOAD_THREADS}"
  --batch-write-size 100
  --debug
)

if [[ "${MIGRATION_LOAD_DURATION}" -gt 0 ]]; then
  asbench_args+=(-T "${MIGRATION_LOAD_DURATION}")
fi

kubectl run "asbench-load-$$" -n "${NAMESPACE}" --restart=Never \
  --image=aerospike/aerospike-tools:latest --rm -i -- \
  asbench "${asbench_args[@]}"

print_namespace_stats
echo "=== Data load complete ==="
