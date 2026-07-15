#!/usr/bin/env bash
# Upgrade AKO one OLM step — argument: target version (e.g. 4.3.0)
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_main_kubecontext

TARGET="${1:?Usage: upgrade-step-olm.sh <version>}"
require_cmd kubectl

CSV_TARGET="aerospike-kubernetes-operator.v${TARGET}"

echo "Upgrading AKO to ${TARGET} via OLM..."
kubectl get installplan -n "${OPERATOR_NAMESPACE}" | grep aerospike || true

# Pin startingCSV so OLM creates an InstallPlan for the exact ladder step.
_installed_csv="$(kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
echo "Pinning subscription startingCSV to ${CSV_TARGET} (installed: ${_installed_csv:-unknown})..."
kubectl patch subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" --type merge \
  -p "{\"spec\":{\"startingCSV\":\"${CSV_TARGET}\"}}"

approve_installplan_for_csv() {
  local csv_name="$1"
  local deadline=$((SECONDS + 300))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    local ip approved
    ip="$(kubectl get installplan -n "${OPERATOR_NAMESPACE}" --no-headers 2>/dev/null \
      | grep "${csv_name}" | awk '{print $1}' | head -1 || true)"
    if [[ -n "${ip}" ]]; then
      approved="$(kubectl get installplan "${ip}" -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.spec.approved}' 2>/dev/null || true)"
      if [[ "${approved}" != "true" ]]; then
        echo "Approving InstallPlan ${ip} for ${csv_name}..."
        kubectl patch installplan "${ip}" -n "${OPERATOR_NAMESPACE}" --type merge -p '{"spec":{"approved":true}}'
      else
        echo "InstallPlan ${ip} for ${csv_name} already approved"
      fi
      return 0
    fi
    echo "  Waiting for InstallPlan for ${csv_name}..."
    sleep 10
  done
  echo "ERROR: InstallPlan for ${csv_name} not found within 5 minutes" >&2
  echo "Pending Aerospike InstallPlans:" >&2
  kubectl get installplan -n "${OPERATOR_NAMESPACE}" | grep aerospike || true
  return 1
}

approve_installplan_for_csv "${CSV_TARGET}"

echo "Waiting for CSV ${CSV_TARGET}..."
if ! kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  "csv/${CSV_TARGET}" -n "${OPERATOR_NAMESPACE}" --timeout=600s; then
  echo "ERROR: CSV ${CSV_TARGET} did not reach Succeeded within timeout" >&2
  kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep aerospike || true
  exit 1
fi

"$(dirname "$0")/verify-ako-version.sh" "${TARGET}"
