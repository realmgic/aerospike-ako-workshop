#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
require_cmd eksctl
require_cmd aws

ensure_upgrade_lab_kubecontext

: "${UPGRADE_LAB_NODEGROUP_NAME:=ng-upgrade-lab}"

echo "Upgrading nodegroup to K8s ${UPGRADE_LAB_K8S_VERSION_TARGET}..."
eksctl upgrade nodegroup \
  --cluster "${UPGRADE_LAB_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --name "${UPGRADE_LAB_NODEGROUP_NAME}" \
  --kubernetes-version "${UPGRADE_LAB_K8S_VERSION_TARGET}"

echo "Waiting for nodegroup to become ACTIVE..."
aws eks wait nodegroup-active \
  --cluster-name "${UPGRADE_LAB_CLUSTER_NAME}" \
  --nodegroup-name "${UPGRADE_LAB_NODEGROUP_NAME}" \
  --region "${AWS_REGION}"

echo "Nodegroup upgrade complete."
