#!/usr/bin/env bash
# Install AKO via OLM at AKO_VERSION_START (k8s-setup.sh lines 35-41)
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env

require_cmd kubectl
require_cmd curl

CSV_NAME="aerospike-kubernetes-operator.v${AKO_VERSION_START}"

olm_diagnose() {
  echo "--- Nodes ---" >&2
  kubectl get nodes -o wide 2>/dev/null || true
  echo "--- olm namespace ---" >&2
  kubectl -n olm get deploy,pods,events --sort-by='.lastTimestamp' 2>/dev/null | tail -30 || true
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

# OperatorHub default install YAML tracks stable channel head (e.g. 4.4.x).
# Pin AKO_VERSION_START so Lab 2.2 can upgrade 4.2.0 → 4.3.0 → 4.4.1 → 4.5.0.
installed_csv="$(kubectl get csv -n "${OPERATOR_NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | grep '^aerospike-kubernetes-operator\.v' | head -1 || true)"
if [[ -n "${installed_csv}" && "${installed_csv}" != "${CSV_NAME}" ]]; then
  echo "ERROR: AKO CSV ${installed_csv} is already installed (expected ${CSV_NAME})." >&2
  echo "Remove the existing subscription and CSV, then re-run:" >&2
  echo "  kubectl delete subscription -n ${OPERATOR_NAMESPACE} --all" >&2
  echo "  kubectl delete csv -n ${OPERATOR_NAMESPACE} ${installed_csv}" >&2
  exit 1
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

echo "Approving InstallPlan for ${CSV_NAME}..."
approved=0
for _ in $(seq 1 60); do
  while read -r ip; do
    [[ -z "${ip}" ]] && continue
    kubectl patch installplan "${ip}" -n "${OPERATOR_NAMESPACE}" --type merge -p '{"spec":{"approved":true}}'
    approved=1
  done < <(kubectl get installplan -n "${OPERATOR_NAMESPACE}" --no-headers 2>/dev/null | grep aerospike | awk '{print $1}')
  if [[ "${approved}" -eq 1 ]]; then
    break
  fi
  sleep 5
done

if [[ "${approved}" -eq 0 ]]; then
  echo "WARN No Aerospike InstallPlan found yet — OLM may still be resolving the catalog."
fi

echo "Waiting for CSV ${CSV_NAME}..."
for _ in $(seq 1 120); do
  phase="$(kubectl get csv -n "${OPERATOR_NAMESPACE}" "${CSV_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "${phase}" == "Succeeded" ]]; then
    echo "OK  CSV ${CSV_NAME} Succeeded"
    break
  fi
  if [[ -n "${phase}" ]]; then
    echo "  CSV phase: ${phase}"
  fi
  sleep 5
done

echo "Current CSV:"
kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep aerospike || true

phase="$(kubectl get csv -n "${OPERATOR_NAMESPACE}" "${CSV_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [[ "${phase}" != "Succeeded" ]]; then
  echo "ERROR: CSV ${CSV_NAME} not Succeeded (phase=${phase:-missing})." >&2
  echo "Check catalog version: kubectl get packagemanifest aerospike-kubernetes-operator -n olm -o yaml | grep currentCSV" >&2
  echo "If an older run used operatorhub.io/install YAML, delete subscription my-aerospike-kubernetes-operator and re-run." >&2
  exit 1
fi

echo "Expected: CSV phase Succeeded for v${AKO_VERSION_START}"
