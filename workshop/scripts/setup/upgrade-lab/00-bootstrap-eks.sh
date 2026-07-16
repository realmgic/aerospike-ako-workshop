#!/usr/bin/env bash
set -euo pipefail
UPGRADE_DIR="$(dirname "$0")"
source "${UPGRADE_DIR}/../../lib/common.sh"
load_env
apply_workshop_kubeconfig
require_cmd eksctl

: "${UPGRADE_LAB_NODEGROUP_NAME:=ng-upgrade-lab}"

# eksctl create cluster accepts --kubeconfig; create nodegroup does not — use KUBECONFIG env (set above).
eksctl_cluster_kc_args=()
if [[ -n "${KUBECONFIG:-}" ]]; then
  eksctl_cluster_kc_args=(--kubeconfig "${KUBECONFIG}")
fi

echo "Creating upgrade-lab EKS cluster ${UPGRADE_LAB_CLUSTER_NAME}..."
eksctl create cluster \
  --region "${AWS_REGION}" \
  --name "${UPGRADE_LAB_CLUSTER_NAME}" \
  --zones "${AWS_ZONES}" \
  --version="${UPGRADE_LAB_K8S_VERSION_START}" \
  --without-nodegroup \
  ${eksctl_cluster_kc_args[@]+"${eksctl_cluster_kc_args[@]}"}

"${UPGRADE_DIR}/ensure-nodegroup.sh"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

ensure_kubecontext "${UPGRADE_LAB_CLUSTER_NAME}"
assert_kubecontext "${UPGRADE_LAB_CLUSTER_NAME}"
