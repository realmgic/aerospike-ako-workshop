#!/usr/bin/env bash
# Regenerate server TLS cert and patch tls-server-secret in place (Lab 3.4).
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl openssl

TLS_DIR="${WORKSHOP_ROOT}/secrets/tls"
if [[ -f "${TLS_DIR}/svc_chain.pem" ]]; then
  old_serial="$(openssl x509 -in "${TLS_DIR}/svc_chain.pem" -noout -serial)"
  echo "Current server cert serial (before rotation): ${old_serial}"
fi

"${WORKSHOP_ROOT}/scripts/setup/tls/generate-workshop-pki.sh" --server-only
"${WORKSHOP_ROOT}/scripts/setup/tls/deploy-tls-secrets.sh"

new_serial="$(openssl x509 -in "${TLS_DIR}/svc_chain.pem" -noout -serial)"
echo "=== Server certificate rotated (same secret name: tls-server-secret) ==="
echo "New server cert serial: ${new_serial}"
echo "Client certs (app.pem) unchanged — compare pod container ID before/after."
echo "Wait for Kubernetes secret sync (~60s), then verify new serial on pod-mounted files."
