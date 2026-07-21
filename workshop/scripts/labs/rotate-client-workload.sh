#!/usr/bin/env bash
# Restart workload Job to pick up rotated client cert (Lab 3.5).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env

echo "=== Rolling workload from v1 to v2 client cert ==="
echo "Stopping workload (was using cert from tls-client-app-secret)..."
"${WORKSHOP_ROOT}/scripts/labs/run-lab-workload.sh" stop || true
echo "Starting workload with v2 client cert (app.pem from tls-client-app-secret)..."
"${WORKSHOP_ROOT}/scripts/labs/run-lab-workload.sh" --pki start
echo "Run ./scripts/labs/run-lab-workload.sh status to confirm TPS (v2 auth)."
echo "v1 cert still valid server-side until blacklist is applied (Lab 3.5 Step 3)."
