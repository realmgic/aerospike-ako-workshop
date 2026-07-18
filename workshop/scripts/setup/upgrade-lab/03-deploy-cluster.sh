#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
source "$(dirname "$0")/../../lib/cluster-storage.sh"
load_env
ensure_upgrade_lab_kubecontext
export CLUSTER_NAME="${UPGRADE_LAB_CLUSTER_NAME}"
require_cmd kubectl

storage="$(resolve_cluster_storage 2.6)"
manifest="$(resolve_cluster_manifest upgrade-lab-dim-cluster "${storage}")"

kubectl apply -f "${manifest}"
echo "Upgrade-lab 3-node cluster deployed (${storage})."
