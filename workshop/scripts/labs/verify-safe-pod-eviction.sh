#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_main_kubecontext

deploy="$(ako_operator_deployment_name)"
failed=0

# Find ValidatingWebhookConfiguration that admits pods/eviction (AKO name varies by install path).
_find_eviction_webhook() {
  local name=""
  if command -v jq >/dev/null 2>&1; then
    name="$(kubectl get validatingwebhookconfiguration -o json 2>/dev/null \
      | jq -r '.items[] | select(.webhooks[]?.rules[]? | (.resources[]? == "pods/eviction")) | .metadata.name' \
      | head -1)"
  fi
  if [[ -z "${name}" ]]; then
    name="$(kubectl get validatingwebhookconfiguration -o name 2>/dev/null \
      | sed 's|.*/||' | grep -iE 'aerospikeeviction|aerospike-operator-validating-webhook' | head -1 || true)"
    if [[ -n "${name}" ]] && ! kubectl get validatingwebhookconfiguration "${name}" \
      -o jsonpath='{.webhooks[*].rules[*].resources}' 2>/dev/null | grep -q 'pods/eviction'; then
      name=""
    fi
  fi
  echo "${name}"
}

if ! kubectl -n "${OPERATOR_NAMESPACE}" get "deployment/${deploy}" >/dev/null 2>&1; then
  echo "ERROR: deployment/${deploy} not found in ${OPERATOR_NAMESPACE}" >&2
  if [[ "${DEPLOY_PATH}" == "helm" ]]; then
    echo "Hint: Helm path uses ${HELM_OPERATOR_RELEASE}, not aerospike-operator-controller-manager" >&2
  else
    echo "Hint: OLM path uses deployment/aerospike-operator-controller-manager" >&2
  fi
  exit 1
fi

env_dump="$(kubectl -n "${OPERATOR_NAMESPACE}" get "deployment/${deploy}" \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"="}{.value}{"\n"}{end}')"

if grep -q 'ENABLE_SAFE_POD_EVICTION=true' <<< "${env_dump}"; then
  echo "OK  operator env ENABLE_SAFE_POD_EVICTION=true (deployment/${deploy})"
else
  echo "FAIL operator env missing ENABLE_SAFE_POD_EVICTION=true (deployment/${deploy})" >&2
  failed=1
fi

if [[ "${DEPLOY_PATH}" == "helm" ]]; then
  if command -v helm >/dev/null 2>&1; then
    helm_values="$(helm get values "${HELM_OPERATOR_RELEASE}" -n "${OPERATOR_NAMESPACE}" -o yaml 2>/dev/null || true)"
    if grep -qE 'enable:\s*true' <<< "${helm_values}" && grep -q 'safePodEviction' <<< "${helm_values}"; then
      echo "OK  helm values safePodEviction.enable=true"
    else
      echo "WARN helm values missing safePodEviction.enable=true — re-apply: helm upgrade ${HELM_OPERATOR_RELEASE} ... -f helm/operator-values.yaml" >&2
    fi
  fi
fi

webhook="$(_find_eviction_webhook)"
if [[ -n "${webhook}" ]]; then
  echo "OK  validating webhook (pods/eviction): ${webhook}"
else
  echo "FAIL validating webhook for pods/eviction not found" >&2
  echo "Hint: re-apply safe pod eviction (Path A patch or Path B helm/operator-values.yaml)" >&2
  failed=1
fi

if kubectl -n "${OPERATOR_NAMESPACE}" rollout status "deployment/${deploy}" --timeout=120s; then
  echo "OK  deployment/${deploy} Ready"
else
  echo "FAIL deployment/${deploy} not Ready" >&2
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi

echo "Safe pod eviction verification passed (DEPLOY_PATH=${DEPLOY_PATH})."
