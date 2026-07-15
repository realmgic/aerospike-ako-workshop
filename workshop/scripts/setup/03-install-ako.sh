#!/usr/bin/env bash
# Install AKO via OLM or Helm (Lab 0.3) — dispatches on DEPLOY_PATH
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_main_kubecontext

SETUP_DIR="$(dirname "$0")"

case "${DEPLOY_PATH}" in
  olm)
    "${SETUP_DIR}/olm/setup-all-olm.sh"
    ;;
  helm)
    "${SETUP_DIR}/helm/setup-all-helm.sh"
    ;;
  *)
    echo "ERROR: DEPLOY_PATH must be 'olm' or 'helm', got: ${DEPLOY_PATH}" >&2
    exit 1
    ;;
esac

echo "AKO install complete (Lab 0.3, DEPLOY_PATH=${DEPLOY_PATH})."
