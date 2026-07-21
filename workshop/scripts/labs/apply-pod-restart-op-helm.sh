#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/cluster-storage.sh"
load_env
ensure_main_kubecontext
require_cmd helm

build_cluster_helm_value_args pod-restart-op
chart_version="$(resolve_cluster_helm_chart_version)"

helm repo add aerospike "${HELM_REPO}" 2>/dev/null || true
helm repo update

helm upgrade --install "${HELM_CLUSTER_RELEASE}" aerospike/aerospike-cluster \
  --namespace "${NAMESPACE}" \
  --version="${chart_version}" \
  "${CLUSTER_HELM_VALUE_ARGS[@]}"

echo "Applied PodRestart operation (Helm, ${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}})."
