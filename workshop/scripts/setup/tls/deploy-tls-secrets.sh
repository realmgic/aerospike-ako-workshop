#!/usr/bin/env bash
# Deploy TLS/PKI secrets to the cluster (idempotent kubectl apply).
#
# Usage:
#   ./scripts/setup/tls/deploy-tls-secrets.sh
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_target_kubecontext() {
  ensure_main_kubecontext
}
ensure_target_kubecontext

require_cmd kubectl

TLS_DIR="${WORKSHOP_ROOT}/secrets/tls"

if [[ ! -f "${TLS_DIR}/cacert.pem" ]]; then
  echo "ERROR: ${TLS_DIR}/cacert.pem not found — run generate-workshop-pki.sh first" >&2
  exit 1
fi

echo "Deploying TLS secrets to cluster ${CLUSTER_NAME} (context: $(current_kube_context))"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic tls-ca-secret \
  --from-file=cacert.pem="${TLS_DIR}/cacert.pem" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic tls-server-secret \
  --from-file=svc_chain.pem="${TLS_DIR}/svc_chain.pem" \
  --from-file=svc_key.pem="${TLS_DIR}/svc_key.pem" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic tls-client-admin-secret \
  --from-file=admin.pem="${TLS_DIR}/admin.pem" \
  --from-file=admin.key="${TLS_DIR}/admin.key" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic tls-client-app-secret \
  --from-file=app.pem="${TLS_DIR}/app.pem" \
  --from-file=app.key="${TLS_DIR}/app.key" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic tls-client-exporter-secret \
  --from-file=exporter.pem="${TLS_DIR}/exporter.pem" \
  --from-file=exporter.key="${TLS_DIR}/exporter.key" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic tls-ako-client-secret \
  --from-file=cacert.pem="${TLS_DIR}/cacert.pem" \
  --from-file=ako_client.pem="${TLS_DIR}/ako_client.pem" \
  --from-file=ako_client.key="${TLS_DIR}/ako_client.key" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "TLS secrets:"
kubectl -n "${NAMESPACE}" get secret tls-ca-secret tls-server-secret tls-client-app-secret tls-ako-client-secret
