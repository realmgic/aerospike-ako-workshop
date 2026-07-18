#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"
load_env
require_cmd kubectl
require_cmd aws

ensure_upgrade_lab_kubecontext

: "${UPGRADE_LAB_NODEGROUP_NAME:=ng-upgrade-lab}"

fail=0

echo "=== Post-upgrade validation ==="

cluster_version="$(aws eks describe-cluster --name "${UPGRADE_LAB_CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query 'cluster.version' --output text)"
cluster_status="$(aws eks describe-cluster --name "${UPGRADE_LAB_CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query 'cluster.status' --output text)"
echo "EKS cluster: version=${cluster_version} status=${cluster_status}"

if [[ "${cluster_version}" == "${UPGRADE_LAB_K8S_VERSION_TARGET}" ]]; then
  echo "OK  EKS version ${cluster_version}"
else
  echo "FAIL EKS version ${cluster_version} (expected ${UPGRADE_LAB_K8S_VERSION_TARGET})"
  fail=1
fi

if [[ "${cluster_status}" == "ACTIVE" ]]; then
  echo "OK  cluster ACTIVE"
else
  echo "FAIL cluster status ${cluster_status} (expected ACTIVE)"
  fail=1
fi

running="$(kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster
if [[ "${running:-0}" -ge "${UPGRADE_LAB_AEROSPIKE_SIZE}" ]]; then
  echo "OK  ${running}/${UPGRADE_LAB_AEROSPIKE_SIZE} Aerospike pods Running"
else
  echo "FAIL ${running}/${UPGRADE_LAB_AEROSPIKE_SIZE} Aerospike pods Running"
  fail=1
fi

phase="$(kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.status.phase}' 2>/dev/null || echo unknown)"
echo "AerospikeCluster phase: ${phase}"
if [[ "${phase}" == "Completed" ]]; then
  echo "OK  AerospikeCluster phase Completed"
else
  echo "FAIL AerospikeCluster phase ${phase} (expected Completed)"
  fail=1
fi

kubelet_minor="${UPGRADE_LAB_K8S_VERSION_TARGET}"
node_count="$(kubectl get nodes -l "alpha.eksctl.io/nodegroup-name=${UPGRADE_LAB_NODEGROUP_NAME}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
kubelet_ok=0
while read -r node kubelet; do
  [[ -z "${node}" ]] && continue
  echo "    node ${node}: kubelet ${kubelet}"
  if [[ "${kubelet}" == *"${kubelet_minor}"* ]]; then
    kubelet_ok=$((kubelet_ok + 1))
  fi
done < <(kubectl get nodes -l "alpha.eksctl.io/nodegroup-name=${UPGRADE_LAB_NODEGROUP_NAME}" \
  -o custom-columns=NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion --no-headers 2>/dev/null)

if [[ "${kubelet_ok:-0}" -ge "${node_count:-0}" ]] && [[ "${node_count:-0}" -ge "${UPGRADE_LAB_NODE_COUNT}" ]]; then
  echo "OK  ${kubelet_ok}/${node_count} node(s) on kubelet ${kubelet_minor}"
else
  echo "FAIL ${kubelet_ok}/${node_count} node(s) on kubelet ${kubelet_minor} (expected ${UPGRADE_LAB_NODE_COUNT})"
  fail=1
fi

engine="$(kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster \
  -o jsonpath='{.spec.aerospikeConfig.namespaces[0].storage-engine.type}' 2>/dev/null || echo unknown)"
echo "Storage engine: ${engine}"

if [[ "${engine}" == device ]]; then
  pvc_count="$(kubectl -n "${NAMESPACE}" get pvc -l aerospike.com/cr=aerocluster --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo "Block PVCs: ${pvc_count}"
fi

cluster_size="$(kubectl run "aerospike-tool-verify-$$" -n "${NAMESPACE}" --restart=Never \
  --image=aerospike/aerospike-tools:latest --rm -i -- \
  asinfo -h aerocluster -U admin -P admin123 -v cluster-size 2>/dev/null | tr -d '[:space:]' || true)"

if [[ "${cluster_size}" == "${UPGRADE_LAB_AEROSPIKE_SIZE}" ]]; then
  echo "OK  asinfo cluster-size=${cluster_size}"
else
  echo "FAIL asinfo cluster-size=${cluster_size:-unknown} (expected ${UPGRADE_LAB_AEROSPIKE_SIZE})"
  fail=1
fi

if [[ "${fail}" -eq 0 ]]; then
  echo "Post-upgrade validation: PASS"
else
  echo "Post-upgrade validation: FAIL"
  exit 1
fi
