#!/usr/bin/env bash
# Reset Karpenter workload NodePools/NodeClaims after a failed or partial apply.
# Keeps EC2NodeClass (idempotent). Re-run 02-ensure-workload-nodepool.sh afterward.
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
source "$(dirname "$0")/../../lib/nodepool-zones.sh"
source "$(dirname "$0")/../../lib/karpenter-teardown.sh"
load_env
ensure_main_kubecontext

require_cmd kubectl

if [[ "${NODE_PROVISIONING}" != "karpenter" ]]; then
  echo "ERROR: NODE_PROVISIONING must be karpenter (got: ${NODE_PROVISIONING})" >&2
  exit 1
fi

echo "=== Resetting Karpenter workload pools on ${CLUSTER_NAME} ==="
reset_karpenter_workload_pools_quick

echo "OK  Workload NodePools cleared (EC2NodeClass retained)."
echo "Re-apply: ./scripts/setup/02-ensure-workload-nodepool.sh"
