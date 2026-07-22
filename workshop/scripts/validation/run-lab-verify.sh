#!/usr/bin/env bash
# Run verification for a lab ID from LAB_REGISTRY
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env

LAB_ID="${1:?Usage: run-lab-verify.sh <lab-id> e.g. 1.1}"

case "${LAB_ID}" in
  0.1) "$(dirname "$0")/../setup/01-validate-client.sh" ;;
  0.6) "$(dirname "$0")/../setup/08-validate-environment.sh" ;;
  1.1|1.2|1.3|1.4)
    echo "=== Node validation (lab ${LAB_ID}) ==="
    "$(dirname "$0")/../labs/lab-nodes.sh" "${LAB_ID}" validate
    "$(dirname "$0")/../verify-cluster.sh"
    ;;
  1.*|2.*) "$(dirname "$0")/../verify-cluster.sh" ;;
  3.*)
    echo "Section 3 (TLS/PKI) has a scripted end-to-end test: ./testing/run-lab.sh ${LAB_ID}"
    echo "(run 3.1 first — it generates the PKI/TLS secrets later 3.x labs depend on)."
    exit 0
    ;;
  *)
    echo "No automated verify for lab ${LAB_ID}; run guide Verify section manually."
    exit 0
    ;;
esac
