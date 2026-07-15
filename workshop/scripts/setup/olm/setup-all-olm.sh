#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
"$(dirname "$0")/01-install-ako.sh"
echo "OLM path setup complete."
