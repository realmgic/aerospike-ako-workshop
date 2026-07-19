#!/usr/bin/env bash
# Apply client certificate blacklist (Lab 3.5) after overlap rotation.
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
echo "Blacklisting certificate serial: ${serial}"

mkdir -p "${WORKSHOP_ROOT}/secrets/tls"
printf '%s\n' "${serial}" > "${WORKSHOP_ROOT}/secrets/tls/revoked.txt"

kubectl -n "${NAMESPACE}" create secret generic tls-cert-blacklist-secret \
  --from-file=revoked.txt="${WORKSHOP_ROOT}/secrets/tls/revoked.txt" \
  --dry-run=client -o yaml | kubectl apply -f -

storage="${EFFECTIVE_CLUSTER_STORAGE:-${CLUSTER_STORAGE}}"
manifest="$(resolve_cluster_manifest dim-cluster-tls-mtls-blacklist "${storage}")"
kubectl apply -f "${manifest}"

echo "=== Certificate blacklist applied — v1 client cert should now be rejected ==="
