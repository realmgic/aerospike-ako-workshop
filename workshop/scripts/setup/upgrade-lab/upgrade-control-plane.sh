#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
require_cmd eksctl
require_cmd aws

ensure_upgrade_lab_kubecontext

echo "Upgrading control plane ${UPGRADE_LAB_CLUSTER_NAME} to ${UPGRADE_LAB_K8S_VERSION_TARGET}..."
eksctl upgrade cluster \
  --name "${UPGRADE_LAB_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --version "${UPGRADE_LAB_K8S_VERSION_TARGET}" \
  --approve

aws eks wait cluster-active --name "${UPGRADE_LAB_CLUSTER_NAME}" --region "${AWS_REGION}"
echo "Control plane upgrade complete."
