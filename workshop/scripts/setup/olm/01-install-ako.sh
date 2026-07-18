#!/usr/bin/env bash
# Install AKO via OLM at AKO_VERSION_START (k8s-setup.sh lines 35-41)
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env

require_cmd kubectl
require_cmd curl

CSV_NAME="aerospike-kubernetes-operator.v${AKO_VERSION_START}"
: "${AKO_UPGRADE_LADDER:=4.2.0,4.3.0,4.4.1,4.5.0}"

ako_csv_version() {
  echo "${1#aerospike-kubernetes-operator.v}"
}

is_ako_ladder_version() {
  local want="$1" v
  IFS=',' read -ra ladder <<< "${AKO_UPGRADE_LADDER}"
  for v in "${ladder[@]}"; do
    v="${v// /}"
    [[ "${v}" == "${want}" ]] && return 0
  done
  return 1
}

skip_if_ako_already_installed() {
  local installed_csv="$1"
  [[ -n "${installed_csv}" ]] || return 1

  local installed_phase installed_version
  installed_phase="$(kubectl get csv -n "${OPERATOR_NAMESPACE}" "${installed_csv}" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${installed_phase}" == "Succeeded" ]] || return 1

  installed_version="$(ako_csv_version "${installed_csv}")"
  if [[ "${installed_csv}" == "${CSV_NAME}" ]]; then
    echo "OK  AKO ${AKO_VERSION_START} already installed (CSV Succeeded) — skipping"
    return 0
  fi

  if is_ako_ladder_version "${installed_version}"; then
    echo "OK  AKO ${installed_version} already installed (CSV Succeeded) — skipping Lab 0.3 install"
    if [[ "${installed_version}" != "${AKO_VERSION_START}" ]]; then
      echo "NOTE: Installed version differs from ${AKO_VERSION_START}."
      echo "      This can happen when OLM auto-resolves a newer stable-channel CSV or when"
      echo "      a prior setup re-run approved an upgrade InstallPlan."
      echo "      Lab 2.2: skip upgrade steps through ${installed_version}; continue from the next ladder version."
    fi
    return 0
  fi

  echo "ERROR: AKO ${installed_csv} is installed (expected ${CSV_NAME})." >&2
  echo "Installed version is not on AKO_UPGRADE_LADDER (${AKO_UPGRADE_LADDER})." >&2
  echo "Skip AKO install and continue setup:" >&2
  echo "  ./scripts/setup/setup-all.sh --from 0.4" >&2
  echo "Or reset the operator and re-run Lab 0.3:" >&2
  echo "  kubectl delete subscription aerospike-kubernetes-operator -n ${OPERATOR_NAMESPACE}" >&2
  echo "  kubectl delete csv -n ${OPERATOR_NAMESPACE} \$(kubectl get csv -n ${OPERATOR_NAMESPACE} -o name | grep aerospike)" >&2
  return 2
}

maybe_skip_ako_install() {
  local active_csv="$1"
  if skip_if_ako_already_installed "${active_csv}"; then
    exit 0
  fi
  local rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    exit 1
  fi
}

resolve_active_ako_csv() {
  local installed current csv phase version

  installed="$(kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" \
    -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
  current="$(kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" \
    -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)"

  for csv in "${installed}" "${current}"; do
    [[ -z "${csv}" ]] && continue
    phase="$(kubectl get csv -n "${OPERATOR_NAMESPACE}" "${csv}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "${phase}" == "Succeeded" ]]; then
      echo "${csv}"
      return 0
    fi
  done

  while read -r csv phase; do
    [[ -z "${csv}" ]] && continue
    [[ "${phase}" == "Succeeded" ]] || continue
    version="$(ako_csv_version "${csv}")"
    if is_ako_ladder_version "${version}"; then
      echo "${csv}"
      return 0
    fi
  done < <(
    kubectl get csv -n "${OPERATOR_NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null \
      | grep '^aerospike-kubernetes-operator\.v' || true
  )

  return 1
}

olm_diagnose() {
  echo "--- Nodes ---" >&2
  kubectl get nodes -o wide 2>/dev/null || true
  echo "--- olm namespace ---" >&2
  kubectl -n olm get deploy,pods,events --sort-by='.lastTimestamp' 2>/dev/null | tail -30 || true
}

ako_diagnose() {
  echo "--- Subscription ---" >&2
  kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" -o yaml 2>/dev/null \
    | tail -40 || true
  echo "--- CSVs ---" >&2
  kubectl get csv -n "${OPERATOR_NAMESPACE}" 2>/dev/null | grep aerospike || true
  echo "--- InstallPlans ---" >&2
  kubectl get installplan -n "${OPERATOR_NAMESPACE}" 2>/dev/null | grep aerospike || true
  echo "--- Operator pods ---" >&2
  kubectl get pods -n "${OPERATOR_NAMESPACE}" -o wide 2>/dev/null || true
  echo "--- Recent operator events ---" >&2
  kubectl get events -n "${OPERATOR_NAMESPACE}" --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true
}

approve_pending_installplans() {
  local csv_name="${1:?csv name required}"
  local deadline=$((SECONDS + 300))
  local approved=0

  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    while read -r ip; do
      [[ -z "${ip}" ]] && continue
      local plan_approved
      plan_approved="$(kubectl get installplan "${ip}" -n "${OPERATOR_NAMESPACE}" \
        -o jsonpath='{.spec.approved}' 2>/dev/null || true)"
      if [[ "${plan_approved}" != "true" ]]; then
        echo "Approving InstallPlan ${ip} for ${csv_name}..."
        kubectl patch installplan "${ip}" -n "${OPERATOR_NAMESPACE}" --type merge -p '{"spec":{"approved":true}}'
      fi
      approved=1
    done < <(kubectl get installplan -n "${OPERATOR_NAMESPACE}" --no-headers 2>/dev/null \
      | grep "${csv_name}" | awk '{print $1}')
    if [[ "${approved}" -eq 1 ]]; then
      return 0
    fi
    sleep 5
  done

  echo "WARN No InstallPlan for ${csv_name} yet — OLM may still be resolving the catalog."
  return 1
}

wait_for_csv_succeeded() {
  local csv_name="$1"
  local timeout="${2:-600}"
  local deadline=$((SECONDS + timeout))

  echo "Waiting for CSV ${csv_name}..."
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    local phase
    phase="$(kubectl get csv -n "${OPERATOR_NAMESPACE}" "${csv_name}" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "${phase}" in
      Succeeded)
        echo "OK  CSV ${csv_name} Succeeded"
        return 0
        ;;
      Failed)
        echo "ERROR: CSV ${csv_name} Failed." >&2
        kubectl describe csv "${csv_name}" -n "${OPERATOR_NAMESPACE}" 2>/dev/null | tail -40 || true
        ako_diagnose
        return 1
        ;;
      Replacing)
        echo "  CSV phase: Replacing (stale CSV from a prior upgrade — will not return to Succeeded)"
        ;;
      "")
        echo "  CSV ${csv_name} not found yet..."
        ;;
      *)
        echo "  CSV phase: ${phase}"
        ;;
    esac
    approve_pending_installplans "${csv_name}" || true
    sleep 5
  done

  echo "ERROR: CSV ${csv_name} did not reach Succeeded within ${timeout}s." >&2
  ako_diagnose
  return 1
}

wait_for_ready_nodes() {
  local timeout="${1:-600}"
  local elapsed=0 ready

  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')"
    if [[ "${ready}" -gt 0 ]]; then
      echo "OK  ${ready} node(s) Ready — proceeding with OLM install"
      return 0
    fi
    echo "Waiting for Ready nodes before OLM install (${elapsed}s/${timeout}s)..."
    sleep 15
    elapsed=$((elapsed + 15))
  done

  echo "ERROR: no Ready nodes after ${timeout}s — olm-operator cannot schedule" >&2
  olm_diagnose
  exit 1
}

ensure_olm() {
  if kubectl get deployment olm-operator -n olm >/dev/null 2>&1; then
    local ready
    ready="$(kubectl -n olm get deployment olm-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    if [[ "${ready:-0}" -ge 1 ]]; then
      echo "OLM already installed and Ready in olm namespace — skipping OLM install."
      return 0
    fi
    echo "olm-operator deployment exists but is not Ready — waiting up to 10m..."
    if kubectl -n olm rollout status deployment/olm-operator --timeout=600s; then
      return 0
    fi
    echo "ERROR: olm-operator rollout failed." >&2
    olm_diagnose
    echo "Recovery: kubectl delete namespace olm --wait=true && re-run this script" >&2
    exit 1
  fi

  wait_for_ready_nodes 600
  echo "Installing OLM ${OLM_VERSION}..."
  # install.sh builds release URLs as ${base_url}/${release}/crds.yaml — release must include the v prefix (e.g. v0.43.0)
  if ! curl -sL "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/install.sh" | bash -s "${OLM_VERSION}"; then
    echo "ERROR: OLM install failed." >&2
    olm_diagnose
    echo "Recovery: kubectl delete namespace olm --wait=true && re-run this script" >&2
    exit 1
  fi
}

OP_REPO="$(operator_repo_path)"
if [[ ! -d "${OP_REPO}" ]]; then
  echo "Cloning aerospike-kubernetes-operator to ${OP_REPO}..."
  mkdir -p "$(dirname "${OP_REPO}")"
  git clone "https://github.com/aerospike/aerospike-kubernetes-operator.git" "${OP_REPO}" || true
fi

ensure_olm

kubectl create namespace "${OPERATOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Detect any active Succeeded AKO CSV (installedCSV, currentCSV, or cluster scan).
active_csv="$(resolve_active_ako_csv 2>/dev/null || true)"
maybe_skip_ako_install "${active_csv}"

target_phase="$(kubectl get csv -n "${OPERATOR_NAMESPACE}" "${CSV_NAME}" \
  -o jsonpath='{.status.phase}' 2>/dev/null || true)"

if [[ "${target_phase}" == "Replacing" ]]; then
  echo "WARN Stale CSV ${CSV_NAME} in Replacing — removing before reinstall..."
  kubectl delete csv "${CSV_NAME}" -n "${OPERATOR_NAMESPACE}" --ignore-not-found --wait=false
  kubectl delete subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" --ignore-not-found --wait=false
  sleep 5
  target_phase=""
fi

if kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" >/dev/null 2>&1; then
  active_csv="$(resolve_active_ako_csv 2>/dev/null || true)"
  maybe_skip_ako_install "${active_csv}"

  echo "AKO subscription exists — waiting for CSV ${CSV_NAME}..."
  approve_pending_installplans "${CSV_NAME}" || true
  wait_for_csv_succeeded "${CSV_NAME}" 600
  echo "Expected: CSV phase Succeeded for v${AKO_VERSION_START}"
  exit 0
fi

echo "Installing AKO ${AKO_VERSION_START} from OperatorHub (startingCSV=${CSV_NAME})..."
kubectl apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: aerospike-kubernetes-operator
  namespace: ${OPERATOR_NAMESPACE}
spec:
  channel: stable
  name: aerospike-kubernetes-operator
  source: operatorhubio-catalog
  sourceNamespace: olm
  startingCSV: ${CSV_NAME}
  installPlanApproval: Manual
EOF

approve_pending_installplans "${CSV_NAME}" || true
wait_for_csv_succeeded "${CSV_NAME}" 600

echo "Current CSV:"
kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep aerospike || true
echo "Expected: CSV phase Succeeded for v${AKO_VERSION_START}"
