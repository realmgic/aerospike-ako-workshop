#!/usr/bin/env bash
# Load records into the cluster (5M x 1KB insert via asbench).
#
# Usage:
#   ./scripts/labs/load-data.sh [--upgrade-lab] [--tls] [--pki]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/asbench-tls.sh"
load_env
require_cmd kubectl

UPGRADE_LAB=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upgrade-lab) UPGRADE_LAB=true ;;
    --tls) AEROSPIKE_TLS_MODE=tls ;;
    --pki) AEROSPIKE_TLS_MODE=pki ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--upgrade-lab] [--tls] [--pki]

Load records into the Aerospike cluster via asbench insert.
  --tls / --pki   Use service TLS (4333) with password or PKI auth
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

run_asbench_pod() {
  local host tls_args=() auth_args=() job_name="asbench-load-$$"
  host="$(asbench_host_arg)"
  build_asbench_tls_args tls_args
  asbench_auth_args auth_args

  local job_file
  job_file="$(mktemp)"
  trap 'rm -f "${job_file}"' RETURN

  {
    cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
EOF
    tls_job_volumes_yaml
    cat <<EOF
      containers:
        - name: asbench
          image: aerospike/aerospike-tools:latest
EOF
    tls_job_volume_mounts_yaml
    cat <<EOF
          command:
            - asbench
            - -h
            - ${host}
EOF
    for arg in "${auth_args[@]}"; do printf '            - "%s"\n' "${arg}"; done
    cat <<EOF
            - -n
            - ${MIGRATION_LOAD_NAMESPACE}
            - -k
            - "${MIGRATION_LOAD_RECORDS}"
            - -o
            - S${MIGRATION_LOAD_OBJECT_SIZE}
            - -w
            - I
            - -z
            - "${MIGRATION_LOAD_THREADS}"
            - --batch-write-size
            - "100"
            - --debug
EOF
    if [[ "${MIGRATION_LOAD_DURATION}" -gt 0 ]]; then
      printf '            - -T\n            - "%s"\n' "${MIGRATION_LOAD_DURATION}"
    fi
    for arg in "${tls_args[@]}"; do printf '            - "%s"\n' "${arg}"; done
  } > "${job_file}"

  kubectl apply -f "${job_file}"
  kubectl -n "${NAMESPACE}" wait --for=condition=complete "job/${job_name}" --timeout=3600s
  kubectl -n "${NAMESPACE}" logs "job/${job_name}"
  kubectl -n "${NAMESPACE}" delete job "${job_name}" --ignore-not-found
}

print_namespace_stats() {
  echo "=== Namespace ${MIGRATION_LOAD_NAMESPACE} stats ==="
  local host tls_args=() auth_args=()
  host="$(asbench_host_arg)"
  build_asbench_tls_args tls_args
  asbench_auth_args auth_args
  kubectl run "aerospike-tool-stats-$$" -n "${NAMESPACE}" --restart=Never \
    --image=aerospike/aerospike-tools:latest --rm -i -- \
    asadm -h "${host}" "${auth_args[@]}" "${tls_args[@]}" -e "info" 2>/dev/null || true
}

ensure_target_kubecontext

echo "=== Load data (TLS mode: ${AEROSPIKE_TLS_MODE}) ==="
validate_cluster_exists
echo "Loading ${MIGRATION_LOAD_RECORDS} records into namespace ${MIGRATION_LOAD_NAMESPACE}..."
run_asbench_pod
print_namespace_stats
echo "=== Data load complete ==="
