#!/usr/bin/env bash
# testing/labs/3.4.sh — Lab 3.4: Server Certificate Rotation
#
# Non-optional path: on the live mTLS+PKIOnly cluster, capture the server cert
# serial + aerocluster-0-0 container ID, run rotate-server-cert.sh (patches
# tls-server-secret in place), then assert the on-disk serial changed, the pod
# container was NOT restarted (hitless reload), and the PKI workload keeps
# running. Replaces the guide's manual "watch TPS / compare serial" steps.
set -euo pipefail
LAB_ID="3.4"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/tls-helpers.sh"

require_cmd openssl
TLS_DIR="${WORKSHOP_ROOT}/secrets/tls"

# Predecessor guard (standalone runs).
if ! kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
  fail_lab "Lab 3.4 requires the Lab 3.3 mTLS/PKIOnly cluster — run testing/run-lab.sh 3.1..3.3 first"
fi

"${LABS}/prepare-lab.sh" 3.4 --skip-reset
wait_pods_running "aerospike.com/cr=aerocluster" 3 600
wait_cr_phase Completed 600

log_info "Ensuring background PKI workload is running..."
"${LABS}/run-lab-workload.sh" stop || true
"${LABS}/run-lab-workload.sh" --pki start
workload_running || fail_lab "Lab 3.4: PKI workload Job did not become active"

POD="$(kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
assert_not_empty "${POD}" "target pod for container-ID comparison" || fail_lab "Lab 3.4: could not resolve an aerocluster pod"

serial_before="$(pem_serial "${TLS_DIR}/svc_chain.pem")"
cid_before="$(pod_container_id "${POD}")"
assert_not_empty "${serial_before}" "server cert serial (before)" || fail_lab "Lab 3.4: could not read svc_chain.pem serial"
assert_not_empty "${cid_before}" "container ID (before, ${POD})" || fail_lab "Lab 3.4: could not read container ID"
log_info "Before rotation: serial=${serial_before} container=${cid_before}"

log_info "Rotating server certificate (patches tls-server-secret in place)..."
"${WORKSHOP_SCRIPTS}/setup/tls/rotate-server-cert.sh"

log_info "Waiting for kubelet secret sync + Aerospike TLS file reload (~75s)..."
sleep 75

serial_after="$(pem_serial "${TLS_DIR}/svc_chain.pem")"
cid_after="$(pod_container_id "${POD}")"
log_info "After rotation: serial=${serial_after} container=${cid_after}"

if [[ "${serial_before}" == "${serial_after}" ]]; then
  fail_lab "Lab 3.4: server cert serial did not change after rotation (${serial_after})"
fi
log_pass "server cert serial changed: ${serial_before} -> ${serial_after}"

assert_eq "${cid_after}" "${cid_before}" "aerocluster pod container unchanged (hitless reload)" || \
  fail_lab "Lab 3.4: pod container restarted during server cert rotation (expected hitless)"

workload_running || fail_lab "Lab 3.4: PKI workload not running after rotation"
log_info "Confirming PKI auth still works with rotated server cert..."
run_asadm_pki "info" "${TLS_APP_SECRET}" || fail_lab "Lab 3.4: PKI auth failed after server cert rotation"

assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 3.4 final CR phase mismatch"

echo "=== Lab 3.4: PASS ==="
