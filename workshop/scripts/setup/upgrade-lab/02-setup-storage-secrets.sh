#!/usr/bin/env bash
# Secrets only — no block/local storage needed for upgrade-lab dim cluster
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_upgrade_lab_kubecontext
export CLUSTER_NAME="${UPGRADE_LAB_CLUSTER_NAME}"
"$(dirname "$0")/../07-deploy-secrets.sh"
