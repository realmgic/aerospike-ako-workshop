#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
"$(dirname "$0")/00-install-cert-manager.sh"
"$(dirname "$0")/01-install-ako.sh"
echo "Helm path AKO install complete."
