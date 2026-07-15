#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
require_cmd eksctl

ensure_upgrade_lab_kubecontext

: "${UPGRADE_LAB_NODEGROUP_NAME:=ng-upgrade-lab}"

echo "Upgrading nodegroup to K8s ${UPGRADE_LAB_K8S_VERSION_TARGET}..."
eksctl upgrade nodegroup \
  --cluster "${UPGRADE_LAB_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --name "${UPGRADE_LAB_NODEGROUP_NAME}" \
  --kubernetes-version "${UPGRADE_LAB_K8S_VERSION_TARGET}"

echo "Nodegroup upgrade initiated."
