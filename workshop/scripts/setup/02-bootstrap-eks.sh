#!/usr/bin/env bash
# Bootstrap main EKS cluster — dispatches on NODE_PROVISIONING (eksctl | karpenter).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
apply_workshop_kubeconfig

require_cmd eksctl
require_cmd kubectl
require_cmd aws

SETUP_DIR="$(dirname "$0")"
KARPENTER_DIR="${SETUP_DIR}/karpenter"

kc_args=()
if [[ -n "${KUBECONFIG:-}" ]]; then
  kc_args=(--kubeconfig "${KUBECONFIG}")
fi

case "${NODE_PROVISIONING}" in
  eksctl)
    echo "Creating EKS cluster ${CLUSTER_NAME} in ${AWS_REGION} (K8s ${K8S_VERSION}) — control plane only..."
    eksctl create cluster \
      --region "${AWS_REGION}" \
      --name "${CLUSTER_NAME}" \
      --zones "${AWS_ZONES}" \
      --version="${K8S_VERSION}" \
      --without-nodegroup \
      ${kc_args[@]+"${kc_args[@]}"}

    echo "Done. Workload nodepool: ./scripts/setup/02-ensure-workload-nodepool.sh (step 0.2-nodes)"
    ;;
  karpenter)
    echo "Creating EKS cluster ${CLUSTER_NAME} in ${AWS_REGION} (K8s ${K8S_VERSION}) — Karpenter path..."
    CLUSTER_CONFIG="${WORKSHOP_ROOT}/clusters/main-cluster-karpenter.yaml"
    if [[ ! -f "${CLUSTER_CONFIG}" ]]; then
      echo "ERROR: missing ${CLUSTER_CONFIG}" >&2
      exit 1
    fi
    require_cmd envsubst
    export CLUSTER_NAME AWS_REGION K8S_VERSION KARPENTER_SYSTEM_NODEGROUP
    export KARPENTER_SYSTEM_NODE_TYPE KARPENTER_SYSTEM_NODE_COUNT SSH_PUBLIC_KEY
    IFS=',' read -r NODE_ZONE_A NODE_ZONE_B _ <<< "${AWS_ZONES},,"
    export NODE_ZONE_A NODE_ZONE_B
    envsubst < "${CLUSTER_CONFIG}" | eksctl create cluster -f - ${kc_args[@]+"${kc_args[@]}"}

    echo "Installing Karpenter controller..."
    "${KARPENTER_DIR}/00-install-controller.sh"

    echo "System nodes:"
    kubectl get nodes -o wide
    echo "Done. Workload NodePool: ./scripts/setup/02-ensure-workload-nodepool.sh (step 0.2-nodes)"
    ;;
  *)
    echo "ERROR: NODE_PROVISIONING must be 'eksctl' or 'karpenter', got: ${NODE_PROVISIONING}" >&2
    exit 1
    ;;
esac

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
ensure_kubecontext "${CLUSTER_NAME}"
assert_kubecontext "${CLUSTER_NAME}"
