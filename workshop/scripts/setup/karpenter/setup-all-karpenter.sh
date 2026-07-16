#!/usr/bin/env bash
# Karpenter bootstrap orchestrator — called from 02-bootstrap-eks.sh karpenter branch.
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env

KARPENTER_DIR="$(dirname "$0")"

echo "=== Karpenter bootstrap (${CLUSTER_NAME}) ==="
"${KARPENTER_DIR}/00-install-controller.sh"
echo "Workload NodePool: ./scripts/setup/02-ensure-workload-nodepool.sh (step 0.2-nodes)"
echo "=== Karpenter bootstrap complete ==="
