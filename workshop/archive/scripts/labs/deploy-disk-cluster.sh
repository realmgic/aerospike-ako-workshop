#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl

kubectl apply -f "${WORKSHOP_ROOT}/manifests/disk-cluster.yaml"
echo "Waiting for AerospikeCluster to reconcile..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l aerospike.com/cr=aerocluster --timeout=600s 2>/dev/null || \
  kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster -w
