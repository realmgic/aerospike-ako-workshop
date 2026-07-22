#!/usr/bin/env bash
# Apply client certificate blacklist file (Lab 3.5): serial → append to revoked.txt → tls-cert-blacklist-secret.
# Does not change AerospikeCluster / Helm release — run deploy-cluster-tls-mtls-blacklist*.sh for that (Step 4).
#
# Usage:
#   ./scripts/labs/apply-cert-blacklist.sh [--cert path/to/old-app.pem]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/cluster-storage.sh"
load_env
ensure_main_kubecontext
require_cmd openssl kubectl

CERT_PATH="${WORKSHOP_ROOT}/secrets/tls/app-v1.pem"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cert) CERT_PATH="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--cert secrets/tls/app-v1.pem]"
      echo "Appends serial to secrets/tls/revoked.txt (one serial per line) and updates tls-cert-blacklist-secret."
      echo "Apply cluster blacklist spec separately: deploy-cluster-tls-mtls-blacklist.sh (Path A) or -helm.sh (Path B)."
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "${CERT_PATH}" ]]; then
  echo "ERROR: certificate not found: ${CERT_PATH}" >&2
  echo "Run rotate-client-cert.sh --save-v1 before rotating to v2." >&2
  exit 1
fi

serial="$(openssl x509 -in "${CERT_PATH}" -noout -serial | cut -d= -f2 | tr '[:upper:]' '[:lower:]')"
REVOKED_FILE="${WORKSHOP_ROOT}/secrets/tls/revoked.txt"
mkdir -p "${WORKSHOP_ROOT}/secrets/tls"

if [[ -f "${REVOKED_FILE}" ]] && grep -qxF "${serial}" "${REVOKED_FILE}"; then
  echo "Serial already listed in ${REVOKED_FILE}: ${serial}"
else
  echo "Appending certificate serial to blacklist: ${serial}"
  printf '%s\n' "${serial}" >> "${REVOKED_FILE}"
fi

echo "Current ${REVOKED_FILE}:"
cat "${REVOKED_FILE}"

kubectl -n "${NAMESPACE}" create secret generic tls-cert-blacklist-secret \
  --from-file=revoked.txt="${REVOKED_FILE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Blacklist secret applied (tls-cert-blacklist-secret) ==="
echo "Next: apply blacklist cluster spec for your deploy path (Lab 3.5 Step 4):"
echo "  Path A: ./scripts/labs/deploy-cluster-tls-mtls-blacklist.sh"
echo "  Path B: ./scripts/labs/deploy-cluster-tls-mtls-blacklist-helm.sh"
echo "Then re-test v1 PKI login (Step 3 command) — should fail."
