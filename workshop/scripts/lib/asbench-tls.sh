#!/usr/bin/env bash
# Shared Aerospike client TLS/PKI flags for asbench and asadm pods.
set -euo pipefail

# AEROSPIKE_TLS_MODE: plain | tls | pki
: "${AEROSPIKE_TLS_MODE:=plain}"
: "${AEROSPIKE_TLS_NAME:=aerocluster}"
: "${AEROSPIKE_TLS_PORT:=4333}"
: "${AEROSPIKE_TLS_CA_MOUNT:=/certs/ca/cacert.pem}"
: "${AEROSPIKE_TLS_CERT_MOUNT:=/certs/client/app.pem}"
: "${AEROSPIKE_TLS_KEY_MOUNT:=/certs/client/app.key}"

asbench_host_arg() {
  if [[ "${AEROSPIKE_TLS_MODE}" != plain ]]; then
    echo "${AEROSPIKE_TLS_NAME}:${AEROSPIKE_TLS_NAME}:${AEROSPIKE_TLS_PORT}"
  else
    echo aerocluster
  fi
}

# Prints TLS/PKI asbench flags, one per line. `local -n` namerefs (bash 4.3+)
# are avoided here since macOS ships bash 3.2 by default; capture output with
# a `while read` loop instead (see build_asbench_tls_args / asbench_auth_args
# call sites in run-lab-workload.sh and load-data.sh).
build_asbench_tls_args() {
  case "${AEROSPIKE_TLS_MODE}" in
    plain) ;;
    tls)
      printf '%s\n' --tls-enable --tls-cafile "${AEROSPIKE_TLS_CA_MOUNT}"
      ;;
    pki)
      printf '%s\n' \
        --tls-enable \
        --tls-cafile "${AEROSPIKE_TLS_CA_MOUNT}" \
        --tls-certfile "${AEROSPIKE_TLS_CERT_MOUNT}" \
        --tls-keyfile "${AEROSPIKE_TLS_KEY_MOUNT}" \
        --auth PKI
      ;;
    *)
      echo "ERROR: invalid AEROSPIKE_TLS_MODE=${AEROSPIKE_TLS_MODE}" >&2
      return 1
      ;;
  esac
}

asbench_auth_args() {
  if [[ "${AEROSPIKE_TLS_MODE}" != pki ]]; then
    printf '%s\n' -U "${AEROSPIKE_AUTH_USER:-app}" -P "${AEROSPIKE_AUTH_PASSWORD:-app123}"
  fi
}

# Reads newline-delimited items from stdin into the named array variable
# (portable bash 3.2+ substitute for `local -n` namerefs / `mapfile -t`).
# The empty-array branch avoids "unbound variable" under `set -u` on bash
# versions before 4.4, which treat `${arr[@]}` on an empty array as unset.
read_args_into() {
  local __var="$1" __line
  local __arr=()
  while IFS= read -r __line; do
    __arr+=("${__line}")
  done
  if [[ ${#__arr[@]} -eq 0 ]]; then
    eval "${__var}=()"
  else
    eval "${__var}=(\"\${__arr[@]}\")"
  fi
}

tls_job_volumes_yaml() {
  if [[ "${AEROSPIKE_TLS_MODE}" == plain ]]; then
    return 0
  fi
  cat <<'EOF'
      volumes:
        - name: tls-ca
          secret:
            secretName: tls-ca-secret
EOF
  if [[ "${AEROSPIKE_TLS_MODE}" == pki ]]; then
    cat <<'EOF'
        - name: tls-client-app
          secret:
            secretName: tls-client-app-secret
EOF
  fi
}

tls_job_volume_mounts_yaml() {
  if [[ "${AEROSPIKE_TLS_MODE}" == plain ]]; then
    return 0
  fi
  cat <<EOF
          volumeMounts:
            - name: tls-ca
              mountPath: /certs/ca
              readOnly: true
EOF
  if [[ "${AEROSPIKE_TLS_MODE}" == pki ]]; then
    cat <<'EOF'
            - name: tls-client-app
              mountPath: /certs/client
              readOnly: true
EOF
  fi
}
