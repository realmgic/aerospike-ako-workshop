#!/usr/bin/env bash
# Collect AKO/Aerospike diagnostics via akoctl collectinfo (Lab 2.1)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_main_kubecontext

OUTPUT_DIR="${1:-/tmp/akoctl-collectinfo-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "${OUTPUT_DIR}"

echo "Collecting diagnostics to ${OUTPUT_DIR}..."
echo "Namespaces: ${NAMESPACE}, ${OPERATOR_NAMESPACE}"

kubectl akoctl collectinfo \
  -n "${NAMESPACE},${OPERATOR_NAMESPACE}" \
  --path "${OUTPUT_DIR}"

echo "Done. Inspect tarball(s) under ${OUTPUT_DIR}:"
ls -la "${OUTPUT_DIR}"
