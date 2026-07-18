#!/usr/bin/env bash
# Deploy secrets to the cluster
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_target_kubecontext

require_cmd kubectl

echo "Deploying secrets to cluster ${CLUSTER_NAME} (context: $(current_kube_context))"

FEATURES="$(features_conf_path)"
DEFAULT_FEATURES="${WORKSHOP_ROOT}/secrets/features.conf"
if [[ ! -f "${FEATURES}" ]]; then
  echo "ERROR: features.conf not found at ${FEATURES}" >&2
  echo "Copy your Aerospike feature-key file to secrets/features.conf" >&2
  exit 1
fi

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

mkdir -p "${WORKSHOP_ROOT}/secrets"
if [[ "${FEATURES}" != "${DEFAULT_FEATURES}" ]]; then
  cp "${FEATURES}" "${DEFAULT_FEATURES}"
  FEATURES="${DEFAULT_FEATURES}"
fi

kubectl -n "${NAMESPACE}" create secret generic aerospike-secret \
  --from-file="${FEATURES}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic auth-secret \
  --from-literal=password='admin123' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic auth-app-secret \
  --from-literal=password='app123' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic auth-exporter-secret \
  --from-literal=password='exporter123' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" get secrets
echo "Secrets deployed. Do not commit features.conf to git."
