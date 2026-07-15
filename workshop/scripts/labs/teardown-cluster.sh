#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_main_kubecontext

if [[ "${DEPLOY_PATH}" == "helm" ]]; then
  helm uninstall "${HELM_CLUSTER_RELEASE}" -n "${NAMESPACE}" 2>/dev/null || true
else
  kubectl delete aerospikecluster aerocluster -n "${NAMESPACE}" --ignore-not-found
fi

# Release PV claims if stuck
pv_list="$(kubectl get pv --no-headers 2>/dev/null | awk -v ns="${NAMESPACE}" 'index($0, ns) {print $1}')" || true
while IFS= read -r pv; do
  [[ -z "${pv}" ]] && continue
  kubectl patch pv "${pv}" -p '{"spec":{"claimRef": null}}' 2>/dev/null || true
done <<< "${pv_list}"

echo "Cluster teardown initiated."
