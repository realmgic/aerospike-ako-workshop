#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/cluster-storage.sh"
load_env
ensure_main_kubecontext
require_cmd helm

storage="${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}}"
values="$(resolve_cluster_helm_values dim-cluster "${storage}")"

helm repo add aerospike "${HELM_REPO}" 2>/dev/null || true
helm repo update

helm upgrade --install "${HELM_CLUSTER_RELEASE}" aerospike/aerospike-cluster \
  --namespace "${NAMESPACE}" --create-namespace \
  --version="${AKO_VERSION_START}" \
  -f "${values}"

echo "Helm cluster deployed (${storage})."
