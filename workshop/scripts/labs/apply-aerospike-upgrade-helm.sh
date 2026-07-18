#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/cluster-storage.sh"
load_env
ensure_main_kubecontext
require_cmd helm

values="$(resolve_cluster_helm_values aerospike-upgrade)"
chart_version="$(resolve_cluster_helm_chart_version)"

helm repo add aerospike "${HELM_REPO}" 2>/dev/null || true
helm repo update

helm upgrade --install "${HELM_CLUSTER_RELEASE}" aerospike/aerospike-cluster \
  --namespace "${NAMESPACE}" \
  --version="${chart_version}" \
  -f "${values}"

echo "Applied Aerospike DB upgrade to 8.1.2.x (Helm, ${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}})."
