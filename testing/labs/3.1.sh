#!/usr/bin/env bash
# testing/labs/3.1.sh — Lab 3.1: Generate PKI Keys and Certificates
#
# Non-optional path: light-reset plain-TCP baseline -> generate workshop PKI
# on the workstation -> deploy TLS secrets -> assert secrets exist, server
# cert carries a SAN, cluster is still plain-TCP 8.1.0.x.
set -euo pipefail
LAB_ID="3.1"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/tls-helpers.sh"

require_cmd openssl

TLS_DIR="${WORKSHOP_ROOT}/secrets/tls"

# Reset stale local blacklist state from a prior failed 3.5 run so we never
# blacklist an outdated serial later in the section.
if [[ -f "${TLS_DIR}/revoked.txt" ]]; then
  log_info "Removing stale ${TLS_DIR}/revoked.txt from a previous run"
  rm -f "${TLS_DIR}/revoked.txt"
fi

"${LABS}/prepare-lab.sh" 3.1

wait_pods_running "aerospike.com/cr=aerocluster" 3 600
wait_cr_phase Completed 600
assert_contains "$(cr_image)" "8.1.0" "baseline DB image (plain TCP)" || fail_lab "Lab 3.1: expected 8.1.0.x baseline image"

log_info "Generating workshop PKI and deploying TLS secrets..."
"${WORKSHOP_SCRIPTS}/setup/tls/generate-workshop-pki.sh"
"${WORKSHOP_SCRIPTS}/setup/tls/deploy-tls-secrets.sh"

assert_tls_secrets_present tls-ca-secret tls-server-secret tls-client-app-secret tls-ako-client-secret || \
  fail_lab "Lab 3.1: required TLS secrets missing after deploy-tls-secrets.sh"

log_info "Verifying server cert carries a SAN (DNS:aerocluster)..."
san="$(openssl x509 -in "${TLS_DIR}/svc_chain.pem" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" || true)"
assert_contains "${san}" "aerocluster" "svc_chain.pem SAN present" || \
  fail_lab "Lab 3.1: svc_chain.pem missing SAN (DNS:aerocluster) — regenerate with generate-workshop-pki.sh --server-only"

log_info "Plain-TCP connectivity evidence (cluster stays plain until Lab 3.2):"
run_asadm_expect_success "show stat like cluster_size" || fail_lab "Lab 3.1: plain-TCP asadm failed"

assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 3.1 final CR phase mismatch"

echo "=== Lab 3.1: PASS ==="
