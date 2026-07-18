#!/usr/bin/env bash
# testing/lib/lab-env.sh
#
# Bootstraps the shared environment for testing/labs/*.sh. Sources the
# existing workshop/ libraries (read-only, unmodified) plus this repo's own
# wait/assert helpers. Each lab script should:
#   LAB_ID="1.1"
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"
# before doing anything else.
set -euo pipefail

TESTING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_workshop_dir="$(cd "${TESTING_ROOT}/../workshop" && pwd)"

# shellcheck disable=SC1091
source "${_workshop_dir}/scripts/lib/common.sh"
# shellcheck disable=SC1091
source "${_workshop_dir}/scripts/lib/cluster-storage.sh"
# shellcheck disable=SC1091
source "${_workshop_dir}/scripts/lib/render-yaml.sh"
# shellcheck disable=SC1091
source "${TESTING_ROOT}/lib/wait-helpers.sh"

load_env
ensure_main_kubecontext

WORKSHOP_SCRIPTS="${WORKSHOP_ROOT}/scripts"
LABS="${WORKSHOP_SCRIPTS}/labs"

echo ""
echo "############################################################"
echo "# Lab ${LAB_ID:-?} — DEPLOY_PATH=${DEPLOY_PATH} NODE_PROVISIONING=${NODE_PROVISIONING} storage=${CLUSTER_STORAGE}"
echo "############################################################"
