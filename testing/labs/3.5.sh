#!/usr/bin/env bash
# testing/labs/3.5.sh — Lab 3.5: Live Client Credential Rotation
#
# Non-optional path on the live mTLS+PKIOnly cluster:
#   1. rotate-client-cert.sh --save-v1  (v1 saved, v2 active; overlap window)
#   2. rotate-client-workload.sh        (workload rolls to v2)
#   2b/3. assert v2 AND v1 both authenticate (overlap)
#   4. apply-cert-blacklist.sh + deploy blacklist spec (path-specific)
#   5. assert v1 rejected, v2 still works, workload still running.
set -euo pipefail
LAB_ID="3.5"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/tls-helpers.sh"

require_cmd openssl
TLS_DIR="${WORKSHOP_ROOT}/secrets/tls"

# Predecessor guard (standalone runs).
if ! kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
  fail_lab "Lab 3.5 requires the Lab 3.3 mTLS/PKIOnly cluster — run testing/run-lab.sh 3.1..3.4 first"
fi

"${LABS}/prepare-lab.sh" 3.5 --skip-reset
wait_pods_running "aerospike.com/cr=aerocluster" 3 600
wait_cr_phase Completed 600

log_info "Starting background PKI workload on the current (v1) client cert..."
"${LABS}/run-lab-workload.sh" stop || true
"${LABS}/run-lab-workload.sh" --pki start
workload_running || fail_lab "Lab 3.5: PKI workload Job did not become active"

# ---- Step 1: save v1, generate v2 ------------------------------------------
log_info "Step 1 — rotate client cert (save v1, activate v2)..."
"${WORKSHOP_SCRIPTS}/setup/tls/rotate-client-cert.sh" --save-v1

v1_serial="$(pem_serial "${TLS_DIR}/app-v1.pem")"
v2_serial="$(pem_serial "${TLS_DIR}/app.pem")"
assert_not_empty "${v1_serial}" "v1 client serial" || fail_lab "Lab 3.5: missing app-v1.pem serial"
assert_not_empty "${v2_serial}" "v2 client serial" || fail_lab "Lab 3.5: missing app.pem serial"
if [[ "${v1_serial}" == "${v2_serial}" ]]; then
  fail_lab "Lab 3.5: v1 and v2 client serials are identical (${v2_serial})"
fi
log_pass "distinct client serials: v1=${v1_serial} v2=${v2_serial}"
assert_tls_secrets_present tls-client-app-v1-secret || fail_lab "Lab 3.5: tls-client-app-v1-secret missing after --save-v1"

# ---- Step 2: roll workload to v2 -------------------------------------------
log_info "Step 2 — roll workload to v2 client cert..."
"${LABS}/rotate-client-workload.sh"
workload_running || fail_lab "Lab 3.5: workload not running after roll to v2"

# ---- Step 2b/3: prove overlap (both v2 and v1 authenticate) ----------------
log_info "Step 2b — v2 client cert authenticates..."
run_asadm_pki "info" "${TLS_APP_SECRET}" || fail_lab "Lab 3.5: v2 PKI auth failed"
log_info "Step 3 — overlap: v1 client cert still authenticates before blacklist..."
run_asadm_pki "info" "${TLS_APP_V1_SECRET}" || fail_lab "Lab 3.5: v1 PKI auth failed during overlap window"

# ---- Step 4: blacklist v1 --------------------------------------------------
log_info "Step 4 — blacklist v1 serial + deploy blacklist cluster spec..."
"${LABS}/apply-cert-blacklist.sh" --cert "${TLS_DIR}/app-v1.pem"
if [[ "${DEPLOY_PATH}" == "helm" ]]; then
  "${LABS}/deploy-cluster-tls-mtls-blacklist-helm.sh"
else
  "${LABS}/deploy-cluster-tls-mtls-blacklist.sh"
fi
wait_cr_phase Completed 900
wait_pods_running "aerospike.com/cr=aerocluster" 3 600

# ---- Step 5: prove v1 rejected, v2 still works -----------------------------
log_info "Step 5 — waiting for v1 blacklist to take effect..."
deadline=$((SECONDS + 180))
while true; do
  if ! run_asadm_pki "info" "${TLS_APP_V1_SECRET}" >/dev/null 2>&1; then
    log_pass "v1 client cert rejected after blacklist"
    break
  fi
  if (( SECONDS > deadline )); then
    fail_lab "Lab 3.5: v1 cert still authenticates 180s after blacklist"
  fi
  sleep 15
done

log_info "v2 client cert still authenticates after blacklist..."
run_asadm_pki "info" "${TLS_APP_SECRET}" || fail_lab "Lab 3.5: v2 PKI auth failed after blacklist"
workload_running || fail_lab "Lab 3.5: workload not running after blacklist"

assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 3.5 final CR phase mismatch"

echo "=== Lab 3.5: PASS ==="
