#!/usr/bin/env bash
# Tear down Section 3 (Security & Authentication): delete aerocluster and TLS/PKI secrets.
#
# Usage:
#   ./scripts/labs/teardown-section-3.sh [--yes] [--keep-local-pki]
#
# Preserves Lab 0.6 secrets (auth-*, aerospike-secret, features). Does not delete EKS or AKO.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/cluster-storage.sh"

assume_yes=false
keep_local_pki=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--yes] [--keep-local-pki]

Delete AerospikeCluster aerocluster and all Section 3 TLS/PKI secrets on the main cluster.
By default also removes workstation files under secrets/tls/.

Options:
  --yes              Skip confirmation prompt
  --keep-local-pki   Keep secrets/tls/ on disk (cluster secrets still deleted)
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) assume_yes=true ;;
    --keep-local-pki) keep_local_pki=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

load_env
ensure_main_kubecontext
require_cmd kubectl

LABS_DIR="$(cd "$(dirname "$0")" && pwd)"
TLS_DIR="${WORKSHOP_ROOT}/secrets/tls"

TLS_SECRETS=(
  tls-ca-secret
  tls-server-secret
  tls-client-admin-secret
  tls-client-app-secret
  tls-client-exporter-secret
  tls-ako-client-secret
  tls-client-app-v1-secret
  tls-cert-blacklist-secret
)

print_plan() {
  echo "=== Section 3 teardown ==="
  echo "Cluster:   ${CLUSTER_NAME} (${AWS_REGION})"
  echo "Namespace: ${NAMESPACE}"
  echo "Remove AerospikeCluster aerocluster (DEPLOY_PATH=${DEPLOY_PATH})"
  echo "Delete TLS secrets:"
  local s
  for s in "${TLS_SECRETS[@]}"; do
    echo "  - ${s}"
  done
  if [[ "${keep_local_pki}" == true ]]; then
    echo "Local PKI: keep ${TLS_DIR}/"
  else
    echo "Local PKI: remove files under ${TLS_DIR}/"
  fi
  echo ""
  echo "Preserves: aerospike-secret, auth-secret, auth-app-secret, auth-exporter-secret, EKS, AKO"
}

confirm_teardown() {
  if [[ "${assume_yes}" == true ]]; then
    return 0
  fi
  print_plan
  read -r -p "Proceed? [y/N] " reply
  case "${reply}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) echo "Aborted."; exit 0 ;;
  esac
}

confirm_teardown
print_plan
echo ""

echo "Stopping lab workload (best-effort)..."
"${LABS_DIR}/run-lab-workload.sh" stop 2>/dev/null || true

echo "Deleting Aerospike cluster..."
"${LABS_DIR}/teardown-cluster.sh"

if kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1 \
    || kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster --no-headers 2>/dev/null | grep -q .; then
  echo "Waiting for aerocluster removal..."
  wait_for_cluster_gone 300 || true
fi

echo "Deleting TLS/PKI secrets..."
for s in "${TLS_SECRETS[@]}"; do
  kubectl -n "${NAMESPACE}" delete secret "${s}" --ignore-not-found
done

if [[ "${keep_local_pki}" == false ]]; then
  if [[ -d "${TLS_DIR}" ]]; then
    rm -rf "${TLS_DIR:?}"/*
    echo "Removed local PKI files under ${TLS_DIR}/"
  else
    echo "No local directory ${TLS_DIR}/ (skip)"
  fi
else
  echo "Kept local PKI under ${TLS_DIR}/ (--keep-local-pki)"
fi

echo ""
echo "=== Section 3 teardown complete ==="
echo "To run Section 1/2 labs: ./scripts/labs/prepare-lab.sh 2.1 (or deploy baseline cluster)."
echo "To run Section 3 again: ./scripts/setup/tls/generate-workshop-pki.sh then Lab 3.1 steps."
