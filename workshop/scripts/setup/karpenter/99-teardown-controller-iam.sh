#!/usr/bin/env bash
# Delete the raw IAM role/policy that 00-install-controller.sh creates directly via `aws iam`
# (NODE_ROLE_NAME, CONTROLLER_POLICY_NAME). Unlike the eksctl-managed IRSA role/ServiceAccount,
# these aren't tracked by any CloudFormation stack, so `eksctl delete cluster` never removes
# them — call this after cluster teardown to avoid leaking them across workshop runs.
# Safe to re-run: every AWS call is best-effort and ignores "not found" errors.
set -uo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env

require_cmd aws

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
CONTROLLER_POLICY_NAME="KarpenterControllerPolicy-${CLUSTER_NAME}"

echo "Removing Karpenter controller IAM role/policy for ${CLUSTER_NAME}..."

aws iam remove-role-from-instance-profile \
  --instance-profile-name "${NODE_ROLE_NAME}" \
  --role-name "${NODE_ROLE_NAME}" 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name "${NODE_ROLE_NAME}" 2>/dev/null || true

for pol in AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly AmazonSSMManagedInstanceCore; do
  aws iam detach-role-policy --role-name "${NODE_ROLE_NAME}" \
    --policy-arn "arn:aws:iam::aws:policy/${pol}" 2>/dev/null || true
done
aws iam delete-role --role-name "${NODE_ROLE_NAME}" 2>/dev/null || true

aws iam delete-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${CONTROLLER_POLICY_NAME}" 2>/dev/null || true

echo "Done: ${NODE_ROLE_NAME} + ${CONTROLLER_POLICY_NAME} removed (or already gone)."
