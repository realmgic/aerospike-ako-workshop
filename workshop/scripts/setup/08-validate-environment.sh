#!/usr/bin/env bash
# Post-setup platform validation (Section 0 gate)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/zone-check.sh"
load_env
ensure_main_kubecontext

fail=0

echo "=== Environment validation (NODE_PROVISIONING=${NODE_PROVISIONING}) ==="

# Workload nodes (Lab 1.1 pool) — created in step 0.2-nodes
if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
  if kubectl -n "${KARPENTER_NAMESPACE}" get deploy karpenter >/dev/null 2>&1; then
    ready="$(kubectl -n "${KARPENTER_NAMESPACE}" get deploy karpenter -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    if [[ "${ready:-0}" -ge 1 ]]; then
      echo "OK  Karpenter controller Ready"
    else
      echo "FAIL Karpenter controller not Ready"
      fail=1
    fi
  else
    echo "FAIL Karpenter deployment missing"
    fail=1
  fi
  workload_nodes="$(kubectl get nodes -l 'workshop.aerospike.com/workload=aerospike' --no-headers 2>/dev/null | grep -c Ready || true)"
  if [[ "${workload_nodes}" -ge "${NODE_COUNT}" ]]; then
    echo "OK  ${workload_nodes} Karpenter workload nodes Ready (NodePool ${KARPENTER_NODEPOOL_NAME})"
  else
    echo "FAIL ${workload_nodes}/${NODE_COUNT} Karpenter workload nodes Ready (NodePool ${KARPENTER_NODEPOOL_NAME})"
    fail=1
  fi
else
  ready_nodes="$(kubectl get nodes -l "alpha.eksctl.io/nodegroup-name=${NODEGROUP_NAME}" --no-headers 2>/dev/null | grep -c Ready || true)"
  if [[ "${ready_nodes}" -ge "${NODE_COUNT}" ]]; then
    echo "OK  ${ready_nodes} workload nodes Ready (nodegroup ${NODEGROUP_NAME})"
  else
    echo "FAIL ${ready_nodes}/${NODE_COUNT} workload nodes Ready (nodegroup ${NODEGROUP_NAME})"
    fail=1
  fi
fi

# NVMe bootstrap DaemonSet applied (readiness after Lab 1.1 nodes)
if kubectl -n kube-system get ds nvme-bootstrap >/dev/null 2>&1; then
  echo "OK  nvme-bootstrap DaemonSet present"
else
  echo "FAIL nvme-bootstrap DaemonSet missing"
  fail=1
fi

# Local volume cleanup controller
if kubectl -n kube-system get deploy local-volume-node-cleanup-controller >/dev/null 2>&1; then
  cleanup_ready="$(kubectl -n kube-system get deploy local-volume-node-cleanup-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
  if [[ "${cleanup_ready:-0}" -ge 1 ]]; then
    echo "OK  local-volume-node-cleanup-controller"
  else
    echo "FAIL local-volume-node-cleanup-controller not Ready"
    fail=1
  fi
else
  echo "FAIL local-volume-node-cleanup-controller missing"
  fail=1
fi

# Operator
if [[ "${DEPLOY_PATH}" == "olm" ]]; then
  phase=$(kubectl get csv -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.items[?(@.spec.displayName=="Aerospike Kubernetes Operator")].status.phase}' 2>/dev/null || echo "")
  if [[ "${phase}" == *Succeeded* ]]; then
    echo "OK  AKO CSV Succeeded"
  else
    echo "WARN AKO CSV not Succeeded yet: ${phase}"
    fail=1
  fi
else
  if helm list -n "${OPERATOR_NAMESPACE}" | grep -q "${HELM_OPERATOR_RELEASE}"; then
    echo "OK  Helm release ${HELM_OPERATOR_RELEASE}"
  else
    echo "FAIL Helm release not found"
    fail=1
  fi
fi

# Storage
if kubectl get storageclass ssd >/dev/null 2>&1; then
  echo "OK  StorageClass ssd"
else
  echo "FAIL StorageClass ssd missing"
  fail=1
fi

if kubectl get storageclass local-ssd >/dev/null 2>&1; then
  echo "OK  StorageClass local-ssd"
else
  echo "FAIL StorageClass local-ssd missing"
  fail=1
fi

# akoctl (installed in Lab 0.4)
if kubectl krew list 2>/dev/null | grep -q akoctl; then
  echo "OK  akoctl krew plugin"
else
  echo "FAIL akoctl not installed — run ./scripts/setup/04-install-akoctl.sh"
  fail=1
fi

# Secrets
for s in aerospike-secret auth-secret; do
  if kubectl -n "${NAMESPACE}" get secret "${s}" >/dev/null 2>&1; then
    echo "OK  secret ${s}"
  else
    echo "FAIL secret ${s} missing"
    fail=1
  fi
done

# No cluster yet
if kubectl -n "${NAMESPACE}" get aerospikecluster --no-headers 2>/dev/null | grep -q .; then
  echo "WARN AerospikeCluster already exists (expected none after Section 0)"
else
  echo "OK  No AerospikeCluster deployed (expected for Section 0 end state)"
fi

if [[ "${fail}" -eq 0 ]]; then
  echo "Environment ready for lab sections. Run ./scripts/labs/prepare-lab.sh 1.1 to start Section 1 (full reset + re-ensure nodes)."
else
  echo "Environment validation failed."
  exit 1
fi
