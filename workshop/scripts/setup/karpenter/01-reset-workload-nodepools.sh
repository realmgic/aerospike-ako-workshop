#!/usr/bin/env bash
# Reset Karpenter workload NodePools/NodeClaims after a failed or partial apply.
# Keeps EC2NodeClass (idempotent). Re-run 02-ensure-workload-nodepool.sh afterward.
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
source "$(dirname "$0")/../../lib/nodepool-zones.sh"
load_env
ensure_main_kubecontext

require_cmd kubectl

if [[ "${NODE_PROVISIONING}" != "karpenter" ]]; then
  echo "ERROR: NODE_PROVISIONING must be karpenter (got: ${NODE_PROVISIONING})" >&2
  exit 1
fi

delete_bootstrap_deployments_by_name() {
  local prefix="$1"
  read_aws_zones_array
  local zone dep_name
  for zone in "${AWS_ZONES_ARRAY[@]}"; do
    [[ -z "${zone}" ]] && continue
    dep_name="${prefix}-$(zone_resource_suffix "${zone}")"
    echo "  Deleting Deployment ${dep_name}..."
    kubectl delete deployment "${dep_name}" -n kube-system --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
  done
}

echo "=== Resetting Karpenter workload pools on ${CLUSTER_NAME} ==="
echo "Deleting bootstrap Deployments (by name — labels are on pods, not Deployment metadata)..."
delete_bootstrap_deployments_by_name "karpenter-bootstrap"
delete_bootstrap_deployments_by_name "karpenter-vertical-bootstrap"

# Remove any orphaned bootstrap pods (e.g. if a prior label-based delete missed the Deployment).
kubectl delete pod -n kube-system -l app=karpenter-bootstrap --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
kubectl delete pod -n kube-system -l app=karpenter-vertical-bootstrap --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true

echo "Deleting NodeClaims..."
kubectl delete nodeclaim --all --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

echo "Deleting NodePools..."
kubectl delete nodepool --all --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true

echo "OK  Workload NodePools cleared (EC2NodeClass retained)."
echo "Re-apply: ./scripts/setup/02-ensure-workload-nodepool.sh"
