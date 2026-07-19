#!/usr/bin/env bash
# Restart workload Job to pick up rotated client cert (Lab 3.5).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env

"${WORKSHOP_ROOT}/scripts/labs/run-lab-workload.sh" stop || true
"${WORKSHOP_ROOT}/scripts/labs/run-lab-workload.sh" --pki start
