#!/usr/bin/env bash
# EBS CSI + eks_ssd storage class
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_main_kubecontext

require_cmd aws
require_cmd eksctl
require_cmd kubectl

STORAGE_YAML="$(vendor_storage_dir)/eks_ssd_storage_class.yaml"

if [[ ! -f "${STORAGE_YAML}" ]]; then
  echo "ERROR: ${STORAGE_YAML} not found." >&2
  exit 1
fi

kubectl apply -f "${STORAGE_YAML}"

oidc_id=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
echo "OIDC provider id: ${oidc_id}"

eksctl utils associate-iam-oidc-provider --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" --approve

eksctl create iamserviceaccount \
  --region "${AWS_REGION}" \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster "${CLUSTER_NAME}" \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-only \
  --role-name AmazonEKS_EBS_CSI_DriverRole

account_id=$(aws sts get-caller-identity --query Account --output text)
eksctl create addon --name aws-ebs-csi-driver --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" \
  --service-account-role-arn "arn:aws:iam::${account_id}:role/AmazonEKS_EBS_CSI_DriverRole" --force

kubectl get storageclass ssd
echo "Expected: StorageClass ssd exists."
