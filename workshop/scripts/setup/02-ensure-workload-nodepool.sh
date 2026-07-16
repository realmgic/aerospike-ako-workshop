#!/usr/bin/env bash
# Ensure main-cluster workload nodepool (Lab 1.1 pool) — idempotent.
set -euo pipefail
exec "$(dirname "$0")/../labs/lab-nodes.sh" 1.1 ensure
