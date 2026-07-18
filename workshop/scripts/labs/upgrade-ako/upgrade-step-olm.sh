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
# Keep Manual approval so OLM does not auto-skip ladder rungs.
_installed_csv="$(kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
echo "Pinning subscription startingCSV to ${CSV_TARGET} (installed: ${_installed_csv:-unknown})..."
kubectl patch subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" --type merge \
  -p "{\"spec\":{\"startingCSV\":\"${CSV_TARGET}\",\"installPlanApproval\":\"Manual\"}}"

installplan_csv_names() {
  local ip="$1"
  kubectl get installplan "${ip}" -n "${OPERATOR_NAMESPACE}" \
    -o jsonpath='{.spec.clusterServiceVersionNames[*]}' 2>/dev/null || true
}

installplan_csv_count() {
  local csvs="$1"
  local -a csv_array=()
  if [[ -n "${csvs}" ]]; then
    read -ra csv_array <<< "${csvs}"
  fi
  echo "${#csv_array[@]}"
}

installplan_is_single_hop() {
  local ip="$1" csv_name="$2"
  local csvs count
  csvs="$(installplan_csv_names "${ip}")"
  count="$(installplan_csv_count "${csvs}")"
  [[ "${count}" -eq 1 && "${csvs}" == "${csv_name}" ]]
}

reject_multi_hop_installplans() {
  local ip csvs count approved
  while read -r ip; do
    [[ -z "${ip}" ]] && continue
    approved="$(kubectl get installplan "${ip}" -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.spec.approved}' 2>/dev/null || true)"
    [[ "${approved}" == "true" ]] && continue

    csvs="$(installplan_csv_names "${ip}")"
    count="$(installplan_csv_count "${csvs}")"
    [[ "${count}" -le 1 ]] && continue

    echo "WARN Deleting multi-hop InstallPlan ${ip} (CSVs: ${csvs}) — ladder requires one version at a time" >&2
    kubectl delete installplan "${ip}" -n "${OPERATOR_NAMESPACE}" --ignore-not-found
  done < <(kubectl get installplan -n "${OPERATOR_NAMESPACE}" --no-headers 2>/dev/null \
    | grep aerospike | awk '{print $1}' || true)
}

find_pending_installplan_for_csv() {
  local csv_name="$1"
  local ip csvs approved
  while read -r ip; do
    [[ -z "${ip}" ]] && continue
    approved="$(kubectl get installplan "${ip}" -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.spec.approved}' 2>/dev/null || true)"
    [[ "${approved}" == "true" ]] && continue
    if installplan_is_single_hop "${ip}" "${csv_name}"; then
      echo "${ip}"
      return 0
    fi
  done < <(kubectl get installplan -n "${OPERATOR_NAMESPACE}" --no-headers 2>/dev/null \
    | awk -v target="${csv_name}" '$2 == target {print $1}' || true)
  return 1
}

approve_installplan_for_csv() {
  local csv_name="$1"
  local deadline=$((SECONDS + 300))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    reject_multi_hop_installplans
    local ip
    if ip="$(find_pending_installplan_for_csv "${csv_name}")"; then
      echo "Approving InstallPlan ${ip} for ${csv_name}..."
      kubectl patch installplan "${ip}" -n "${OPERATOR_NAMESPACE}" --type merge -p '{"spec":{"approved":true}}'
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

echo "Waiting for subscription installedCSV ${CSV_TARGET}..."
if ! kubectl wait --for=jsonpath='{.status.installedCSV}'="${CSV_TARGET}" \
  subscription/aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" --timeout=600s; then
  echo "ERROR: Subscription did not reach installedCSV ${CSV_TARGET} within timeout" >&2
  kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" -o yaml | tail -20 || true
  kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep aerospike || true
  exit 1
fi

echo "Waiting for CSV ${CSV_TARGET}..."
if ! kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  "csv/${CSV_TARGET}" -n "${OPERATOR_NAMESPACE}" --timeout=600s; then
  echo "ERROR: CSV ${CSV_TARGET} did not reach Succeeded within timeout" >&2
  kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep aerospike || true
  exit 1
fi

echo "Waiting for operator deployment rollout..."
kubectl -n "${OPERATOR_NAMESPACE}" rollout status \
  deployment/aerospike-operator-controller-manager --timeout=300s

"$(dirname "$0")/verify-ako-version.sh" "${TARGET}"
