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

# Populates a nameref array with TLS/PKI asbench flags.
build_asbench_tls_args() {
  local -n _out=$1
  _out=()
  case "${AEROSPIKE_TLS_MODE}" in
    plain) ;;
    tls)
      _out+=(--tls-enable --tls-cafile "${AEROSPIKE_TLS_CA_MOUNT}")
      ;;
    pki)
      _out+=(
        --tls-enable
        --tls-cafile "${AEROSPIKE_TLS_CA_MOUNT}"
        --tls-certfile "${AEROSPIKE_TLS_CERT_MOUNT}"
        --tls-keyfile "${AEROSPIKE_TLS_KEY_MOUNT}"
        --auth PKI
      )
      ;;
    *)
      echo "ERROR: invalid AEROSPIKE_TLS_MODE=${AEROSPIKE_TLS_MODE}" >&2
      return 1
      ;;
  esac
}

asbench_auth_args() {
  local -n _out=$1
  _out=()
  if [[ "${AEROSPIKE_TLS_MODE}" != pki ]]; then
    _out+=(-U "${AEROSPIKE_AUTH_USER:-app}" -P "${AEROSPIKE_AUTH_PASSWORD:-app123}")
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
