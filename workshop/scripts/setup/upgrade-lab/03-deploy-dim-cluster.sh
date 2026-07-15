#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_upgrade_lab_kubecontext
export CLUSTER_NAME="${UPGRADE_LAB_CLUSTER_NAME}"
require_cmd kubectl

kubectl apply -f "${WORKSHOP_ROOT}/manifests/upgrade-lab-dim-cluster.yaml"
echo "Upgrade-lab 3-node in-memory cluster deployed."
