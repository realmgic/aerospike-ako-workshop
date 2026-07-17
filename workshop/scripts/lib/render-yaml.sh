#!/usr/bin/env bash
# Render workshop YAML templates that use NODE_ZONE_A / NODE_ZONE_B.
# Requires load_env() to have run.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

render_workshop_yaml() {
  local file="$1"
  require_cmd envsubst
  envsubst '$NODE_ZONE_A $NODE_ZONE_B' < "${file}"
}
