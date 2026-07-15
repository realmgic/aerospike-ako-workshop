#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_main_kubecontext

UPGRADE_DIR="$(dirname "$0")"
VERSIONS="${UPGRADE_DIR}/versions.env"
if [[ ! -f "${VERSIONS}" ]]; then
  VERSIONS="${UPGRADE_DIR}/versions.env.example"
fi
# shellcheck disable=SC1090
source "${VERSIONS}"

IFS=',' read -ra LADDER <<< "${AKO_UPGRADE_LADDER}"
for ver in "${LADDER[@]:1}"; do
  echo "=== Upgrade step: ${ver} ==="
  "${UPGRADE_DIR}/upgrade-step-helm.sh" "${ver}"
done
