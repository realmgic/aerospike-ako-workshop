#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_main_kubecontext
require_cmd helm

helm repo add aerospike "${HELM_REPO}" 2>/dev/null || true
helm repo update

helm upgrade --install "${HELM_CLUSTER_RELEASE}" aerospike/aerospike-cluster \
  --namespace "${NAMESPACE}" --create-namespace \
  --version="${AKO_VERSION_START}" \
  -f "${WORKSHOP_ROOT}/helm/dim-cluster-values.yaml"

echo "Helm dim cluster deployed."
