#!/usr/bin/env bash
# Install cert-manager for Helm path (AKO admission webhooks)
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env

require_cmd kubectl
require_cmd helm

echo "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

echo "Waiting for cert-manager pods..."
kubectl -n cert-manager wait --for=condition=Ready pod -l app.kubernetes.io/instance=cert-manager --timeout=300s || true
echo "cert-manager installed."
