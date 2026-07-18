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
  _sub_installed="$(kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.status.installedCSV}' 2>/dev/null || echo 'missing')"
  _sub_current="$(kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo 'missing')"
  _sub_state="$(kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.status.state}' 2>/dev/null || echo 'unknown')"
  if [[ "${_sub_installed}" != "${CSV_EXPECTED}" ]]; then
    echo "ERROR: AKO not at ${EXPECTED} (subscription installedCSV=${_sub_installed}, currentCSV=${_sub_current}, state=${_sub_state})" >&2
    if [[ "${_sub_current}" == "${CSV_EXPECTED}" && "${_csv_phase}" == "missing" ]]; then
      echo "NOTE: OLM resolved ${EXPECTED} but the CSV is not installed yet (UpgradePending)." >&2
      echo "      Approve the pending InstallPlan:" >&2
      echo "        ./scripts/labs/upgrade-ako/upgrade-step-olm.sh ${EXPECTED}" >&2
    elif [[ "${_sub_current}" != "${CSV_EXPECTED}" && "${_csv_phase}" == "Succeeded" ]]; then
      echo "NOTE: CSV ${CSV_EXPECTED} still shows Succeeded from a prior step, but OLM has moved on." >&2
      echo "      Continue the ladder from ${_sub_installed#aerospike-kubernetes-operator.v} or reinstall AKO at 4.2.0." >&2
    fi
    kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep aerospike || true
    kubectl get installplan -n "${OPERATOR_NAMESPACE}" | grep aerospike || true
    exit 1
  fi
  if [[ "${_csv_phase}" != "Succeeded" ]]; then
    echo "ERROR: AKO installedCSV is ${EXPECTED} but CSV phase=${_csv_phase}" >&2
    kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep aerospike || true
    exit 1
  fi
  kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep "${CSV_EXPECTED}"
fi

kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.status.phase}' 2>/dev/null && echo || true
echo "Expected AKO version: ${EXPECTED}; Aerospike cluster should remain Completed."
