#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
apply_workshop_kubeconfig
require_cmd eksctl

: "${UPGRADE_LAB_NODEGROUP_NAME:=ng-upgrade-lab}"

kc_args=()
if [[ -n "${KUBECONFIG:-}" ]]; then
  kc_args=(--kubeconfig "${KUBECONFIG}")
fi

echo "Creating upgrade-lab EKS cluster ${UPGRADE_LAB_CLUSTER_NAME}..."
eksctl create cluster \
  --region "${AWS_REGION}" \
  --name "${UPGRADE_LAB_CLUSTER_NAME}" \
  --zones "${AWS_ZONES}" \
  --version="${UPGRADE_LAB_K8S_VERSION_START}" \
  --without-nodegroup \
  "${kc_args[@]}"

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
  --ssh-public-key "${SSH_PUBLIC_KEY}" \
  "${kc_args[@]}"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl get nodes -o wide

ensure_kubecontext "${UPGRADE_LAB_CLUSTER_NAME}"
assert_kubecontext "${UPGRADE_LAB_CLUSTER_NAME}"
