#!/usr/bin/env bash
# Install akoctl and create namespace RBAC (k8s-setup.sh lines 43-56)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_target_kubecontext

require_cmd kubectl

if ! kubectl krew version >/dev/null 2>&1; then
  echo "ERROR: krew not installed. See instructor/client-prerequisites.md" >&2
  exit 1
fi

kubectl krew index add akoctl https://github.com/aerospike/aerospike-kubernetes-operator-ctl.git 2>/dev/null || true
kubectl krew install akoctl/akoctl 2>/dev/null || kubectl krew upgrade akoctl 2>/dev/null || true

echo "Creating namespace RBAC via akoctl..."
kubectl akoctl auth create -n "${NAMESPACE}"

echo "akoctl installed and RBAC created for namespace ${NAMESPACE}."
