#!/usr/bin/env bash
# Upgrade AKO one Helm step — argument: target version (e.g. 4.3.0)
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_main_kubecontext

TARGET="${1:?Usage: upgrade-step-helm.sh <version>}"
require_cmd helm
require_cmd kubectl

echo "Replacing CRDs for AKO ${TARGET}..."
for crd in aerospikeclusters aerospikebackupservices aerospikebackups aerospikerestores; do
  kubectl replace -f "https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/v${TARGET}/config/crd/bases/asdb.aerospike.com_${crd}.yaml"
done

helm repo update
helm upgrade "${HELM_OPERATOR_RELEASE}" aerospike/aerospike-kubernetes-operator \
  --namespace "${OPERATOR_NAMESPACE}" \
  --version="${TARGET}" \
  -f "${WORKSHOP_ROOT}/helm/operator-values.yaml"

kubectl -n "${OPERATOR_NAMESPACE}" rollout status deployment/aerospike-operator-controller-manager --timeout=300s
"$(dirname "$0")/verify-ako-version.sh" "${TARGET}"
