#!/usr/bin/env bash
# testing/lib/tls-helpers.sh
#
# TLS/PKI asadm + secret helpers for the Section 3 lab tests
# (testing/labs/3.*.sh). Sourced by those scripts only (NOT globally in
# lab-env.sh) so the plain-TCP Section 1/2 tests are untouched.
#
# These replace the guide's interactive `kubectl run ... --overrides` asadm
# blocks with scripted, assertion-friendly wrappers. They mount the workshop
# TLS secrets (CA + client cert) into a short-lived pod, run one asadm
# command, and pass/fail based on exit code + output inspection.
#
# Expects testing/lib/lab-env.sh (hence wait-helpers.sh) to have been sourced
# first, so NAMESPACE, LABS, log_pass/log_fail, etc. are available.

: "${AEROSPIKE_TLS_PORT:=4333}"
: "${TLS_CA_SECRET:=tls-ca-secret}"
: "${TLS_APP_SECRET:=tls-client-app-secret}"
: "${TLS_APP_V1_SECRET:=tls-client-app-v1-secret}"
: "${TLS_CA_MOUNT:=/etc/aerospike/tls/ca}"
: "${TLS_CLIENT_MOUNT:=/etc/aerospike/tls/client}"
: "${WORKLOAD_JOB_NAME:=workshop-asbench-workload}"

_tls_host() { echo "aerocluster:aerocluster:${AEROSPIKE_TLS_PORT}"; }

# ---- Secret presence --------------------------------------------------------

assert_tls_secrets_present() {
  local fail=0 s
  for s in "$@"; do
    if kubectl -n "${NAMESPACE}" get secret "${s}" >/dev/null 2>&1; then
      log_pass "secret present: ${s}"
    else
      log_fail "secret missing: ${s}"
      fail=1
    fi
  done
  return "${fail}"
}

# ---- JSON / override plumbing ----------------------------------------------

# Emit a JSON array of the given string args (escaping backslash and quote).
_json_str_array() {
  local out="[" first=1 a
  for a in "$@"; do
    [[ "${first}" -eq 1 ]] && first=0 || out+=","
    a="${a//\\/\\\\}"
    a="${a//\"/\\\"}"
    out+="\"${a}\""
  done
  out+="]"
  printf '%s' "${out}"
}

_vols_ca() { printf '[{"name":"tls-ca","secret":{"secretName":"%s"}}]' "${TLS_CA_SECRET}"; }
_mounts_ca() { printf '[{"name":"tls-ca","mountPath":"%s","readOnly":true}]' "${TLS_CA_MOUNT}"; }

_vols_ca_client() {
  printf '[{"name":"tls-ca","secret":{"secretName":"%s"}},{"name":"tls-client","secret":{"secretName":"%s"}}]' \
    "${TLS_CA_SECRET}" "$1"
}
_mounts_ca_client() {
  printf '[{"name":"tls-ca","mountPath":"%s","readOnly":true},{"name":"tls-client","mountPath":"%s","readOnly":true}]' \
    "${TLS_CA_MOUNT}" "${TLS_CLIENT_MOUNT}"
}

# _asadm_run <podname> <args_json> <vols_json> <mounts_json> -> stdout, exit code
_asadm_run() {
  local podname="$1" args_json="$2" vols_json="$3" mounts_json="$4"
  local overrides
  overrides="$(printf '{"spec":{"containers":[{"name":"%s","image":"aerospike/aerospike-tools:latest","command":["asadm"],"args":%s,"volumeMounts":%s}],"volumes":%s}}' \
    "${podname}" "${args_json}" "${mounts_json}" "${vols_json}")"
  kubectl run "${podname}" -n "${NAMESPACE}" --restart=Never --rm -i \
    --image=aerospike/aerospike-tools:latest \
    --overrides="${overrides}" 2>/dev/null
}

# _asadm_check <out> <cmd> <expect> <label>
_asadm_check() {
  local out="$1" cmd="$2" expect="$3" label="$4"
  echo "${out}"
  if grep -qiE 'not able to connect|connection refused|no credential|bad credential|failed to connect|ERROR:' <<<"${out}"; then
    log_fail "asadm ${label} reported an error: ${cmd}"
    return 1
  fi
  if [[ -n "${expect}" && "${out}" != *"${expect}"* ]]; then
    log_fail "asadm ${label} output missing expected token '${expect}': ${cmd}"
    return 1
  fi
  log_pass "asadm ${label} succeeded: ${cmd}"
  return 0
}

# ---- asadm modes ------------------------------------------------------------

# TLS + password, CA only, no client cert (Lab 3.2). Defaults to admin creds.
run_asadm_tls_password() {
  local cmd="$1" expect="${2:-}"
  local user="${AEROSPIKE_ADMIN_USER:-admin}" pass="${AEROSPIKE_ADMIN_PASSWORD:-admin123}"
  local out
  if ! out="$(_asadm_run "asadm-tls-$$-${RANDOM}" \
      "$(_json_str_array -h "$(_tls_host)" --tls-enable --tls-cafile "${TLS_CA_MOUNT}/cacert.pem" \
        -U "${user}" -P "${pass}" -e "${cmd}")" \
      "$(_vols_ca)" "$(_mounts_ca)")"; then
    log_fail "asadm TLS+password pod failed: ${cmd}"
    return 1
  fi
  _asadm_check "${out}" "${cmd}" "${expect}" "TLS+password"
}

# mTLS + password: client cert AND password (Lab 3.3 Phase A). Defaults app creds.
run_asadm_mtls_password() {
  local cmd="$1" expect="${2:-}"
  local user="${AEROSPIKE_AUTH_USER:-app}" pass="${AEROSPIKE_AUTH_PASSWORD:-app123}"
  local out
  if ! out="$(_asadm_run "asadm-mtls-$$-${RANDOM}" \
      "$(_json_str_array -h "$(_tls_host)" --tls-enable --tls-cafile "${TLS_CA_MOUNT}/cacert.pem" \
        --tls-certfile "${TLS_CLIENT_MOUNT}/app.pem" --tls-keyfile "${TLS_CLIENT_MOUNT}/app.key" \
        -U "${user}" -P "${pass}" -e "${cmd}")" \
      "$(_vols_ca_client "${TLS_APP_SECRET}")" "$(_mounts_ca_client)")"; then
    log_fail "asadm mTLS+password pod failed: ${cmd}"
    return 1
  fi
  _asadm_check "${out}" "${cmd}" "${expect}" "mTLS+password"
}

# PKI auth (no password): client cert as identity (Lab 3.3 Phase B/C, 3.4, 3.5).
# Second arg selects the client secret (v2 default, or tls-client-app-v1-secret).
run_asadm_pki() {
  local cmd="$1" client_secret="${2:-${TLS_APP_SECRET}}" expect="${3:-}"
  local out
  if ! out="$(_asadm_run "asadm-pki-$$-${RANDOM}" \
      "$(_json_str_array -h "$(_tls_host)" --tls-enable --tls-cafile "${TLS_CA_MOUNT}/cacert.pem" \
        --tls-certfile "${TLS_CLIENT_MOUNT}/app.pem" --tls-keyfile "${TLS_CLIENT_MOUNT}/app.key" \
        --auth PKI -e "${cmd}")" \
      "$(_vols_ca_client "${client_secret}")" "$(_mounts_ca_client)")"; then
    log_fail "asadm PKI pod failed (secret ${client_secret}): ${cmd}"
    return 1
  fi
  _asadm_check "${out}" "${cmd}" "${expect}" "PKI(${client_secret})"
}

# Negative check: run the given asadm helper invocation and PASS only if it
# FAILS. Usage: run_asadm_expect_fail "<desc>" run_asadm_pki "info" tls-client-app-v1-secret
run_asadm_expect_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    log_fail "${desc}: expected asadm to fail but it succeeded"
    return 1
  fi
  log_pass "${desc}: asadm rejected as expected"
  return 0
}

# ---- Cert / pod inspection (Lab 3.4) ---------------------------------------

pem_serial() {
  openssl x509 -in "$1" -noout -serial 2>/dev/null | cut -d= -f2
}

pod_container_id() {
  kubectl -n "${NAMESPACE}" get pod "$1" \
    -o jsonpath='{.status.containerStatuses[?(@.name=="aerospike-server")].containerID}' 2>/dev/null
}

# ---- Workload status (non-blocking; run-lab-workload.sh status tails -f) ----

workload_running() {
  local active
  active="$(kubectl -n "${NAMESPACE}" get job "${WORKLOAD_JOB_NAME}" -o jsonpath='{.status.active}' 2>/dev/null)"
  if [[ "${active:-0}" -ge 1 ]]; then
    log_pass "PKI workload Job active (${active} pod)"
    return 0
  fi
  log_fail "PKI workload Job not active (active=${active:-0})"
  return 1
}
