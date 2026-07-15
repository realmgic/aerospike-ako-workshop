#!/usr/bin/env bash
# Minimal AKO install on upgrade-lab cluster (OLM path)
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_upgrade_lab_kubecontext
export CLUSTER_NAME="${UPGRADE_LAB_CLUSTER_NAME}"
"$(dirname "$0")/../olm/01-install-ako.sh"
