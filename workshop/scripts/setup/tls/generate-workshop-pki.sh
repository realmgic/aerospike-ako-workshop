#!/usr/bin/env bash
# Generate workshop TLS/PKI material under secrets/tls/ (gitignored).
#
# Usage:
#   ./scripts/setup/tls/generate-workshop-pki.sh [--server-only] [--client-app-only]
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env

require_cmd openssl

TLS_DIR="${WORKSHOP_ROOT}/secrets/tls"
: "${TLS_CLUSTER_NAME:=aerocluster}"
: "${TLS_CA_DAYS:=3650}"
: "${TLS_CERT_DAYS:=825}"

SERVER_ONLY=false
CLIENT_APP_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-only) SERVER_ONLY=true ;;
    --client-app-only) CLIENT_APP_ONLY=true ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--server-only] [--client-app-only]

Generate workshop CA, server chain, and client certificates (CN = username).
Output: ${TLS_DIR}/

  --server-only       Regenerate server cert/key only (Lab 3.4 rotation)
  --client-app-only   Regenerate app client cert/key only (Lab 3.5 rotation)
EOF
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

mkdir -p "${TLS_DIR}"

sign_cert() {
  local csr="$1" out="$2"
  openssl x509 -req -in "${csr}" \
    -CA "${TLS_DIR}/cacert.pem" -CAkey "${TLS_DIR}/cakey.pem" \
    -CAcreateserial -out "${out}" -days "${TLS_CERT_DAYS}"
}

generate_client() {
  local cn="$1" pem="$2" key="$3"
  openssl genrsa -out "${key}" 2048
  openssl req -new -key "${key}" -out "${TLS_DIR}/.tmp.csr" \
    -subj "/CN=${cn}/O=Aerospike Workshop/C=US"
  sign_cert "${TLS_DIR}/.tmp.csr" "${pem}"
  rm -f "${TLS_DIR}/.tmp.csr"
}

if [[ "${CLIENT_APP_ONLY}" == true ]]; then
  if [[ ! -f "${TLS_DIR}/cacert.pem" || ! -f "${TLS_DIR}/cakey.pem" ]]; then
    echo "ERROR: CA missing — run without --client-app-only first" >&2
    exit 1
  fi
  echo "Regenerating app client certificate..."
  generate_client app "${TLS_DIR}/app.pem" "${TLS_DIR}/app.key"
  echo "OK  ${TLS_DIR}/app.pem"
  exit 0
fi

if [[ "${SERVER_ONLY}" == true ]]; then
  if [[ ! -f "${TLS_DIR}/cacert.pem" || ! -f "${TLS_DIR}/cakey.pem" ]]; then
    echo "ERROR: CA missing — run without --server-only first" >&2
    exit 1
  fi
  echo "Regenerating server certificate..."
  openssl genrsa -out "${TLS_DIR}/svc_key.pem" 2048
  openssl req -new -key "${TLS_DIR}/svc_key.pem" -out "${TLS_DIR}/.tmp.csr" \
    -subj "/CN=${TLS_CLUSTER_NAME}/O=Aerospike Workshop/C=US"
  sign_cert "${TLS_DIR}/.tmp.csr" "${TLS_DIR}/svc.pem"
  rm -f "${TLS_DIR}/.tmp.csr"
  cat "${TLS_DIR}/svc.pem" "${TLS_DIR}/cacert.pem" > "${TLS_DIR}/svc_chain.pem"
  echo "OK  ${TLS_DIR}/svc_chain.pem"
  exit 0
fi

echo "=== Generating workshop PKI in ${TLS_DIR} ==="

openssl genrsa -out "${TLS_DIR}/cakey.pem" 4096
openssl req -new -x509 -days "${TLS_CA_DAYS}" -key "${TLS_DIR}/cakey.pem" \
  -out "${TLS_DIR}/cacert.pem" \
  -subj "/CN=Workshop Aerospike CA/O=Aerospike Workshop/C=US"

openssl genrsa -out "${TLS_DIR}/svc_key.pem" 2048
openssl req -new -key "${TLS_DIR}/svc_key.pem" -out "${TLS_DIR}/.tmp.csr" \
  -subj "/CN=${TLS_CLUSTER_NAME}/O=Aerospike Workshop/C=US"
sign_cert "${TLS_DIR}/.tmp.csr" "${TLS_DIR}/svc.pem"
rm -f "${TLS_DIR}/.tmp.csr"
cat "${TLS_DIR}/svc.pem" "${TLS_DIR}/cacert.pem" > "${TLS_DIR}/svc_chain.pem"

generate_client admin "${TLS_DIR}/admin.pem" "${TLS_DIR}/admin.key"
generate_client app "${TLS_DIR}/app.pem" "${TLS_DIR}/app.key"
generate_client exporter "${TLS_DIR}/exporter.pem" "${TLS_DIR}/exporter.key"
generate_client ako-operator "${TLS_DIR}/ako_client.pem" "${TLS_DIR}/ako_client.key"

chmod 600 "${TLS_DIR}"/*.key "${TLS_DIR}/cakey.pem" 2>/dev/null || true

echo "Generated:"
ls -1 "${TLS_DIR}"/*.pem "${TLS_DIR}"/*.key 2>/dev/null || true
echo "Do not commit secrets/tls/ — see secrets/README.md"
