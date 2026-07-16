#!/usr/bin/env bash
# Apply Karpenter workload NodePool — delegates to Section 0 workload ensure.
set -euo pipefail
exec "$(dirname "$0")/../02-ensure-workload-nodepool.sh"
