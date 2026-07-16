#!/usr/bin/env bash
# Upgrade-lab post-bootstrap: AKO, akoctl, secrets, Aerospike (Lab 2.6 prep).
set -euo pipefail
UPGRADE_DIR="$(dirname "$0")"
source "${UPGRADE_DIR}/../../lib/common.sh"
load_env
export WORKSHOP_KUBECONFIG="$(kubeconfig_path_for_cluster "${UPGRADE_LAB_CLUSTER_NAME}")"
apply_workshop_kubeconfig

restore_main_kubecontext() {
  if cluster_exists "${CLUSTER_NAME}"; then
    export WORKSHOP_KUBECONFIG="$(kubeconfig_path_for_cluster "${CLUSTER_NAME}")"
    apply_workshop_kubeconfig
    ensure_kubecontext "${CLUSTER_NAME}" >/dev/null 2>&1 || true
    echo "Restored kubectl context to main cluster: ${CLUSTER_NAME}"
  fi
}
trap restore_main_kubecontext EXIT

echo "=== Upgrade-lab post-bootstrap ==="
export CLUSTER_NAME="${UPGRADE_LAB_CLUSTER_NAME}"
ensure_upgrade_lab_kubecontext

if ! kubectl get csv -n "${OPERATOR_NAMESPACE}" 2>/dev/null | grep -q aerospike-kubernetes-operator; then
  "${UPGRADE_DIR}/01-install-ako.sh"
else
  echo "AKO already installed on upgrade-lab — skipping 01-install-ako.sh"
fi

if ! command -v kubectl-akoctl >/dev/null 2>&1; then
  "${UPGRADE_DIR}/../04-install-akoctl.sh"
else
  echo "akoctl already installed — skipping 04-install-akoctl.sh"
fi

if ! kubectl -n "${NAMESPACE}" get secret aerospike-secret >/dev/null 2>&1; then
  "${UPGRADE_DIR}/02-setup-storage-secrets.sh"
else
  echo "Secrets already present on upgrade-lab — skipping 02-setup-storage-secrets.sh"
fi

if ! kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
  "${UPGRADE_DIR}/03-deploy-dim-cluster.sh"
else
  echo "AerospikeCluster aerocluster already exists on upgrade-lab — skipping deploy"
fi

echo "=== Upgrade-lab ready for Lab 2.6 ==="
