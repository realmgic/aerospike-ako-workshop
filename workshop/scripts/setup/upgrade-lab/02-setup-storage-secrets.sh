#!/usr/bin/env bash
# Secrets for upgrade-lab — delegates to 07-deploy-secrets.sh (same as main cluster).
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
export WORKSHOP_KUBECONFIG="$(kubeconfig_path_for_cluster "${UPGRADE_LAB_CLUSTER_NAME}")"
apply_workshop_kubeconfig
export CLUSTER_NAME="${UPGRADE_LAB_CLUSTER_NAME}"
ensure_upgrade_lab_kubecontext
"$(dirname "$0")/../07-deploy-secrets.sh"
