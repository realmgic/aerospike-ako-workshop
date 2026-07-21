#!/usr/bin/env bash
# Regenerate app client cert and patch tls-client-app-secret in place (Lab 3.5 overlap).
#
# Usage:
#   ./scripts/setup/tls/rotate-client-cert.sh [--save-v1]
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl openssl

SAVE_V1=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --save-v1) SAVE_V1=true ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--save-v1]"
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

TLS_DIR="${WORKSHOP_ROOT}/secrets/tls"
if [[ "${SAVE_V1}" == true && -f "${TLS_DIR}/app.pem" ]]; then
  cp "${TLS_DIR}/app.pem" "${TLS_DIR}/app-v1.pem"
  cp "${TLS_DIR}/app.key" "${TLS_DIR}/app-v1.key"
  v1_serial="$(openssl x509 -in "${TLS_DIR}/app-v1.pem" -noout -serial)"
  echo "Saved v1 client cert to ${TLS_DIR}/app-v1.pem (${v1_serial})"
  kubectl -n "${NAMESPACE}" create secret generic tls-client-app-v1-secret \
    --from-file=app.pem="${TLS_DIR}/app-v1.pem" \
    --from-file=app.key="${TLS_DIR}/app-v1.key" \
    --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
  echo "Deployed tls-client-app-v1-secret (for overlap demo in Lab 3.5 Step 3)"
fi

"${WORKSHOP_ROOT}/scripts/setup/tls/generate-workshop-pki.sh" --client-app-only

TLS_DIR="${WORKSHOP_ROOT}/secrets/tls"
v2_serial="$(openssl x509 -in "${TLS_DIR}/app.pem" -noout -serial)"
kubectl -n "${NAMESPACE}" create secret generic tls-client-app-secret \
  --from-file=app.pem="${TLS_DIR}/app.pem" \
  --from-file=app.key="${TLS_DIR}/app.key" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== App client certificate rotated (v2 active in tls-client-app-secret) ==="
echo "v2 serial: ${v2_serial}"
if [[ "${SAVE_V1}" == true ]]; then
  echo "Server accepts both v1 and v2 until blacklist is applied."
  echo "Next: ./scripts/labs/rotate-client-workload.sh  (roll workload to v2)"
else
  echo "Restart workload Job to pick up new cert: ./scripts/labs/rotate-client-workload.sh"
fi
