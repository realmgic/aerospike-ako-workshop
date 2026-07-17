#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/render-yaml.sh"
load_env
ensure_main_kubecontext
require_cmd helm

helm repo add aerospike "${HELM_REPO}" 2>/dev/null || true
helm repo update

render_workshop_yaml "${WORKSHOP_ROOT}/helm/rack-cluster-replacement-values.yaml" | helm upgrade --install "${HELM_CLUSTER_RELEASE}" aerospike/aerospike-cluster \
  --namespace "${NAMESPACE}" \
  --version="${AKO_VERSION_START}" \
  -f -

echo "Helm rack replacement cluster deployed."
