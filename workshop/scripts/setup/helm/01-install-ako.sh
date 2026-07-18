#!/usr/bin/env bash
# Install AKO via Helm at AKO_VERSION_START
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env

require_cmd helm
require_cmd kubectl

helm repo add aerospike "${HELM_REPO}" 2>/dev/null || true
helm repo update

echo "Installing AKO ${AKO_VERSION_START} via Helm..."
helm upgrade --install "${HELM_OPERATOR_RELEASE}" aerospike/aerospike-kubernetes-operator \
  --namespace "${OPERATOR_NAMESPACE}" --create-namespace \
  --version="${AKO_VERSION_START}" \
  -f "${WORKSHOP_ROOT}/helm/operator-values.yaml"

kubectl -n "${OPERATOR_NAMESPACE}" rollout status "deployment/${HELM_OPERATOR_RELEASE}" --timeout=300s
helm list -n "${OPERATOR_NAMESPACE}"
echo "Expected: release ${HELM_OPERATOR_RELEASE} at ${AKO_VERSION_START}, operator pods Running."
