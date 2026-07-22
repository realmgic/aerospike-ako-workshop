#!/usr/bin/env bash
# testing/labs/3.3.sh — Lab 3.3: mTLS and PKI Authentication
#
# Non-optional path: prepare-lab.sh 3.3 upgrades TLS-standard to mTLS (Phase A,
# deployed by prepare — do NOT re-deploy). This test then asserts:
#   Phase A — client cert + password works; CA+password (no cert) is rejected.
#   Phase B — PKI auth (client cert as identity, no password) works.
#   Phase C — apply PKIOnly, PKI still works, password path is rejected.
# Finally loads data + starts a PKI workload for Labs 3.4/3.5.
set -euo pipefail
LAB_ID="3.3"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/tls-helpers.sh"

# Predecessor guard (standalone runs).
if ! kubectl -n "${NAMESPACE}" get secret tls-ca-secret >/dev/null 2>&1; then
  fail_lab "Lab 3.3 requires Lab 3.1 TLS secrets — run testing/run-lab.sh 3.1/3.2 first"
fi

"${LABS}/prepare-lab.sh" 3.3

wait_pods_running "aerospike.com/cr=aerocluster" 3 900
wait_cr_phase Completed 900

# ---- Phase A: mTLS (client cert + password) --------------------------------
log_info "Phase A — mTLS: client cert + password..."
run_asadm_mtls_password "info" || fail_lab "Lab 3.3 Phase A: mTLS + password connection failed"

log_info "Phase A negative — CA + password without client cert must be rejected..."
run_asadm_expect_fail "Phase A no-client-cert" run_asadm_tls_password "info" || \
  fail_lab "Lab 3.3 Phase A: connection without client cert unexpectedly succeeded"

# ---- Phase B: PKI auth (no password) ---------------------------------------
log_info "Phase B — PKI auth (client cert as identity, no password)..."
run_asadm_pki "info" "${TLS_APP_SECRET}" || fail_lab "Lab 3.3 Phase B: PKI auth failed"

# ---- Phase C: PKIOnly -------------------------------------------------------
log_info "Phase C — applying PKIOnly cluster spec (DEPLOY_PATH=${DEPLOY_PATH})..."
apply_cluster_change dim-cluster-tls-mtls-pki-only
wait_cr_phase Completed 900
wait_pods_running "aerospike.com/cr=aerocluster" 3 600

log_info "Phase C — PKI auth still works under PKIOnly..."
run_asadm_pki "info" "${TLS_APP_SECRET}" || fail_lab "Lab 3.3 Phase C: PKI auth failed after PKIOnly"

log_info "Phase C negative — password auth must be rejected under PKIOnly..."
run_asadm_expect_fail "Phase C password rejected" run_asadm_mtls_password "info" || \
  fail_lab "Lab 3.3 Phase C: password auth unexpectedly succeeded under PKIOnly"

# ---- Seed data + PKI workload for Labs 3.4/3.5 -----------------------------
log_info "Loading data over PKI and starting background PKI workload..."
"${LABS}/load-data.sh" --pki
"${LABS}/run-lab-workload.sh" stop || true
"${LABS}/run-lab-workload.sh" --pki start
workload_running || fail_lab "Lab 3.3: PKI workload Job did not become active"

assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 3.3 final CR phase mismatch"

echo "=== Lab 3.3: PASS ==="
