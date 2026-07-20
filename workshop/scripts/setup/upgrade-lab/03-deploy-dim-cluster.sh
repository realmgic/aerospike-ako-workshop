#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
source "$(dirname "$0")/../../lib/cluster-storage.sh"
load_env
ensure_upgrade_lab_kubecontext
export CLUSTER_NAME="${UPGRADE_LAB_CLUSTER_NAME}"
require_cmd kubectl

manifest="$(resolve_cluster_manifest dim-cluster dim)"

kubectl apply -f "${manifest}"
echo "Upgrade-lab 3-node in-memory cluster deployed."
