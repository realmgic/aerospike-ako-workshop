#!/usr/bin/env bash
# Regenerate server TLS cert and patch tls-server-secret in place (Lab 3.4).
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl

"${WORKSHOP_ROOT}/scripts/setup/tls/generate-workshop-pki.sh" --server-only
"${WORKSHOP_ROOT}/scripts/setup/tls/deploy-tls-secrets.sh"

echo "=== Server certificate rotated (same secret name: tls-server-secret) ==="
echo "Wait for Kubernetes secret sync (~60s), then verify new notBefore on pod-mounted files."
