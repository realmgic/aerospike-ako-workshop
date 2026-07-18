#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl

echo "=== AerospikeCluster ==="
kubectl -n "${NAMESPACE}" get aerospikecluster 2>/dev/null || true

echo "=== Pods ==="
kubectl -n "${NAMESPACE}" get pods -o wide 2>/dev/null || true

echo "=== PVCs ==="
kubectl -n "${NAMESPACE}" get pvc 2>/dev/null || true

echo "=== StatefulSets ==="
kubectl -n "${NAMESPACE}" get statefulset 2>/dev/null || true

if kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
  echo "=== CR Status ==="
  kubectl -n "${NAMESPACE}" describe aerospikecluster aerocluster | sed -n '/Status:/,$p' | head -40
fi

echo "=== Operator logs (last 50) ==="
kubectl -n "${OPERATOR_NAMESPACE}" logs "deployment/$(ako_operator_deployment_name)" --tail=50 2>/dev/null || true
