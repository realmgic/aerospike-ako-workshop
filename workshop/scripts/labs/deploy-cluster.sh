#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/cluster-storage.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl

storage="${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}}"
manifest="$(resolve_cluster_manifest dim-cluster "${storage}")"

kubectl apply -f "${manifest}"
echo "Waiting for AerospikeCluster to reconcile..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l aerospike.com/cr=aerocluster --timeout=600s 2>/dev/null || \
  kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster -w
