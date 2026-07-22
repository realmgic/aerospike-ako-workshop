#!/usr/bin/env bash
# testing/labs/3.2.sh — Lab 3.2: TLS Only (Encryption in Transit)
#
# Non-optional path: prepare-lab.sh 3.2 upgrades the plain baseline to service
# TLS on port 4333 (deploys tls-standard itself — do NOT re-deploy here) ->
# assert TLS+password works on 4333 and plain TCP still works on 3000.
set -euo pipefail
LAB_ID="3.2"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/tls-helpers.sh"

# Predecessor guard (standalone runs): Lab 3.1 deploys the TLS secrets.
if ! kubectl -n "${NAMESPACE}" get secret tls-ca-secret >/dev/null 2>&1; then
  fail_lab "Lab 3.2 requires Lab 3.1 TLS secrets — run testing/run-lab.sh 3.1 first"
fi

"${LABS}/prepare-lab.sh" 3.2

wait_pods_running "aerospike.com/cr=aerocluster" 3 600
wait_cr_phase Completed 600
assert_contains "$(cr_image)" "8.1.0" "TLS standard baseline image" || fail_lab "Lab 3.2: expected 8.1.0.x image"

log_info "Connecting over TLS + password on port ${AEROSPIKE_TLS_PORT} (CA only, no client cert)..."
run_asadm_tls_password "show stat like cluster_size" "cluster_size" || \
  fail_lab "Lab 3.2: TLS+password connection on 4333 failed"

log_info "Confirming plain TCP port 3000 still works..."
run_asadm_expect_success "show stat like cluster_size" "cluster_size" || \
  fail_lab "Lab 3.2: plain-TCP port 3000 no longer reachable"

assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 3.2 final CR phase mismatch"

echo "=== Lab 3.2: PASS ==="
