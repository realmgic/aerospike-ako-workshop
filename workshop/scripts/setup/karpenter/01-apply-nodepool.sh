#!/usr/bin/env bash
# Apply Karpenter workload NodePool — delegates to Lab 1.1 node ensure.
set -euo pipefail
exec "$(dirname "$0")/../../labs/lab-nodes.sh" 1.1 ensure
