#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
require_cmd kubectl
require_cmd aws

ensure_upgrade_lab_kubecontext

echo "=== Post-upgrade validation ==="
aws eks describe-cluster --name "${UPGRADE_LAB_CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query 'cluster.{version:version,status:status}'

kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster
phase=$(kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
echo "AerospikeCluster phase: ${phase}"

engine=$(kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster \
  -o jsonpath='{.spec.aerospikeConfig.namespaces[0].storage-engine.type}' 2>/dev/null || echo "unknown")
echo "Storage engine: ${engine}"

if [[ "${engine}" == device ]]; then
  pvc_count=$(kubectl -n "${NAMESPACE}" get pvc -l aerospike.com/cr=aerocluster --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "Block PVCs: ${pvc_count}"
fi

echo "Expected: 3 pods Running, phase Completed"
