#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/cluster-storage.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl

storage="${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}}"
manifest="$(resolve_cluster_manifest dim-cluster-maintenance "${storage}")"

kubectl apply -f "${manifest}"
echo "Maintenance cluster manifest applied (${storage})."
