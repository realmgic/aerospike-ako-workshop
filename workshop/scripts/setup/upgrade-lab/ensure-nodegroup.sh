#!/usr/bin/env bash
# Ensure upgrade-lab managed nodegroup exists and nodes are Ready.
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
apply_workshop_kubeconfig
require_cmd eksctl
require_cmd kubectl

: "${UPGRADE_LAB_NODEGROUP_NAME:=ng-upgrade-lab}"

upgrade_lab_nodegroup_exists() {
  eksctl get nodegroup \
    --cluster "${UPGRADE_LAB_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --name "${UPGRADE_LAB_NODEGROUP_NAME}" >/dev/null 2>&1
}

wait_upgrade_lab_nodes() {
  local expected="$1"
  local timeout="${2:-900}"
  local elapsed=0 ready

  echo "Waiting for ${expected} upgrade-lab node(s) Ready (timeout ${timeout}s)..."
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    ready="$(kubectl get nodes -l "alpha.eksctl.io/nodegroup-name=${UPGRADE_LAB_NODEGROUP_NAME}" --no-headers 2>/dev/null \
      | awk '$2=="Ready"{c++} END{print c+0}')"
    echo "  ${UPGRADE_LAB_NODEGROUP_NAME} nodes Ready: ${ready}/${expected}"
    if [[ "${ready}" -ge "${expected}" ]]; then
      kubectl get nodes -o wide
      return 0
    fi
    sleep 15
    elapsed=$((elapsed + 15))
  done

  echo "ERROR: timed out waiting for upgrade-lab nodes" >&2
  kubectl get nodes -o wide 2>/dev/null || true
  eksctl get nodegroup --cluster "${UPGRADE_LAB_CLUSTER_NAME}" --region "${AWS_REGION}" 2>/dev/null || true
  exit 1
}

if upgrade_lab_nodegroup_exists; then
  echo "Nodegroup ${UPGRADE_LAB_NODEGROUP_NAME} already exists on ${UPGRADE_LAB_CLUSTER_NAME}"
else
  echo "Creating nodegroup ${UPGRADE_LAB_NODEGROUP_NAME} on ${UPGRADE_LAB_CLUSTER_NAME}..."
  eksctl create nodegroup \
    --cluster "${UPGRADE_LAB_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --node-zones "${UPGRADE_LAB_NODE_ZONE:-${NODE_ZONE}}" \
    --name "${UPGRADE_LAB_NODEGROUP_NAME}" \
    --node-type "${UPGRADE_LAB_NODE_TYPE}" \
    --nodes "${UPGRADE_LAB_NODE_COUNT}" \
    --nodes-min "${UPGRADE_LAB_NODE_COUNT}" \
    --nodes-max "${UPGRADE_LAB_NODE_COUNT}" \
    --ssh-access \
    --ssh-public-key "${SSH_PUBLIC_KEY}"
fi

wait_upgrade_lab_nodes "${UPGRADE_LAB_NODE_COUNT}"
