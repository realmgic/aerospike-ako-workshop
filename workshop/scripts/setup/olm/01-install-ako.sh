#!/usr/bin/env bash
# Install AKO via OLM at AKO_VERSION_START (k8s-setup.sh lines 35-41)
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env

require_cmd kubectl
require_cmd curl

CSV_NAME="aerospike-kubernetes-operator.v${AKO_VERSION_START}"

OP_REPO="$(operator_repo_path)"
if [[ ! -d "${OP_REPO}" ]]; then
  echo "Cloning aerospike-kubernetes-operator to ${OP_REPO}..."
  mkdir -p "$(dirname "${OP_REPO}")"
  git clone "https://github.com/aerospike/aerospike-kubernetes-operator.git" "${OP_REPO}" || true
fi

if ! kubectl get deployment olm-operator -n olm >/dev/null 2>&1; then
  echo "Installing OLM ${OLM_VERSION}..."
  # install.sh builds release URLs as ${base_url}/${release}/crds.yaml — release must include the v prefix (e.g. v0.43.0)
  curl -sL "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/install.sh" | bash -s "${OLM_VERSION}"
else
  echo "OLM already installed in olm namespace — skipping OLM install."
fi

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
