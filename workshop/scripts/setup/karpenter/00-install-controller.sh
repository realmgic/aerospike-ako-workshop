#!/usr/bin/env bash
# Install Karpenter controller (Helm) with IRSA on the main cluster.
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
ensure_main_kubecontext

require_cmd aws
require_cmd eksctl
require_cmd helm
require_cmd kubectl

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
CLUSTER_ENDPOINT="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query "cluster.endpoint" --output text)"
NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
CONTROLLER_ROLE_NAME="KarpenterControllerRole-${CLUSTER_NAME}"
CONTROLLER_POLICY_NAME="KarpenterControllerPolicy-${CLUSTER_NAME}"

echo "Installing Karpenter ${KARPENTER_VERSION} on ${CLUSTER_NAME}..."

# Discovery tags for subnets and cluster security group
CLUSTER_SG="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)"
aws ec2 create-tags --region "${AWS_REGION}" \
  --resources "${CLUSTER_SG}" \
  --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" 2>/dev/null || true

for subnet in $(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query "cluster.resourcesVpcConfig.subnetIds[]" --output text); do
  aws ec2 create-tags --region "${AWS_REGION}" \
    --resources "${subnet}" \
    --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" 2>/dev/null || true
done

# Node IAM role + instance profile
if ! aws iam get-role --role-name "${NODE_ROLE_NAME}" >/dev/null 2>&1; then
  aws iam create-role --role-name "${NODE_ROLE_NAME}" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  for pol in AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly AmazonSSMManagedInstanceCore; do
    aws iam attach-role-policy --role-name "${NODE_ROLE_NAME}" \
      --policy-arn "arn:aws:iam::aws:policy/${pol}"
  done
  aws iam create-instance-profile --instance-profile-name "${NODE_ROLE_NAME}" >/dev/null 2>&1 || true
  aws iam add-role-to-instance-profile \
    --instance-profile-name "${NODE_ROLE_NAME}" \
    --role-name "${NODE_ROLE_NAME}" 2>/dev/null || true
fi

# Controller IAM policy
if ! aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${CONTROLLER_POLICY_NAME}" >/dev/null 2>&1; then
  aws iam create-policy --policy-name "${CONTROLLER_POLICY_NAME}" \
    --policy-document file://"${WORKSHOP_ROOT}/scripts/setup/karpenter/karpenter-controller-policy.json" >/dev/null
fi

eksctl create iamserviceaccount \
  --cluster="${CLUSTER_NAME}" \
  --region="${AWS_REGION}" \
  --namespace="${KARPENTER_NAMESPACE}" \
  --name=karpenter \
  --role-name "${CONTROLLER_ROLE_NAME}" \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${CONTROLLER_POLICY_NAME}" \
  --override-existing-serviceaccounts \
  --approve

CONTROLLER_ROLE_ARN="$(aws iam get-role --role-name "${CONTROLLER_ROLE_NAME}" \
  --query Role.Arn --output text)"

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.clusterEndpoint=${CLUSTER_ENDPOINT}" \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${CONTROLLER_ROLE_ARN}" \
  --set "controller.resources.requests.cpu=1" \
  --set "controller.resources.requests.memory=1Gi" \
  --set "controller.resources.limits.cpu=1" \
  --set "controller.resources.limits.memory=1Gi" \
  --wait

# Schedule controller on system nodegroup (tainted ${KARPENTER_SYSTEM_NODEGROUP})
kubectl -n "${KARPENTER_NAMESPACE}" patch deployment karpenter --type=strategic -p '{
  "spec": {
    "template": {
      "spec": {
        "tolerations": [{"key":"role","operator":"Equal","value":"system","effect":"NoSchedule"}],
        "nodeSelector": {"role": "system"}
      }
    }
  }
}' 2>/dev/null || true
kubectl -n "${KARPENTER_NAMESPACE}" rollout status deployment/karpenter --timeout=300s

echo "Karpenter controller Ready. Node role: ${NODE_ROLE_NAME}"
