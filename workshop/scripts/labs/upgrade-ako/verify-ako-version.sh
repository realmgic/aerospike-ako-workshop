#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_main_kubecontext

EXPECTED="${1:?Usage: verify-ako-version.sh <version>}"

CSV_EXPECTED="aerospike-kubernetes-operator.v${EXPECTED}"

if [[ "${DEPLOY_PATH}" == "helm" ]]; then
  helm list -n "${OPERATOR_NAMESPACE}" | grep "${HELM_OPERATOR_RELEASE}"
else
  _csv_phase="$(kubectl get csv -n "${OPERATOR_NAMESPACE}" "${CSV_EXPECTED}" -o jsonpath='{.status.phase}' 2>/dev/null || echo 'missing')"
  _sub_current="$(kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo 'missing')"
  if [[ "${_csv_phase}" != "Succeeded" || "${_sub_current}" != "${CSV_EXPECTED}" ]]; then
    echo "ERROR: AKO not at ${EXPECTED} (CSV phase=${_csv_phase}, subscription currentCSV=${_sub_current})" >&2
    kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep aerospike || true
    exit 1
  fi
  kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep "${CSV_EXPECTED}"
fi

kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.status.phase}' 2>/dev/null && echo || true
echo "Expected AKO version: ${EXPECTED}; Aerospike cluster should remain Completed."
