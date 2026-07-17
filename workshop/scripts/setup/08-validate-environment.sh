#!/usr/bin/env bash
# Post-setup platform validation (Section 0 gate)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/zone-check.sh"
source "$(dirname "$0")/../lib/local-storage.sh"
source "$(dirname "$0")/../lib/nodepool-zones.sh"
load_env
ensure_main_kubecontext

fail=0
workload_nodes=0

count_baseline_workload_nodes() {
  kubectl get nodes -l "workshop.aerospike.com/node-pool=baseline" --no-headers 2>/dev/null \
    | grep -c Ready || true
}

echo "=== Environment validation (NODE_PROVISIONING=${NODE_PROVISIONING}) ==="

# Workload nodes (baseline per-AZ pools) — created in step 0.2-nodes
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
fi

workload_nodes="$(count_baseline_workload_nodes)"
if [[ "${workload_nodes}" -ge "${NODE_COUNT}" ]]; then
  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    echo "OK  ${workload_nodes} baseline workload nodes Ready (per-AZ NodePools ${KARPENTER_NODEPOOL_NAME}-*)"
  else
    echo "OK  ${workload_nodes} baseline workload nodes Ready (per-AZ nodegroups ${NODEGROUP_NAME}-*)"
  fi
else
  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    echo "FAIL ${workload_nodes}/${NODE_COUNT} baseline workload nodes Ready (per-AZ NodePools ${KARPENTER_NODEPOOL_NAME}-*)"
  else
    echo "FAIL ${workload_nodes}/${NODE_COUNT} baseline workload nodes Ready (per-AZ nodegroups ${NODEGROUP_NAME}-*)"
  fi
  fail=1
fi
print_zone_distribution "${NODE_TYPE}"
if ! assert_multi_az_nodes warn "${NODE_TYPE}"; then
  fail=1
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

# Local-ssd PV discovery — restart provisioner after nvme-bootstrap (idempotent safety net)
nvme_desired="$(nvme_bootstrap_desired)"
if [[ "${nvme_desired}" -gt 0 ]]; then
  wait_nvme_bootstrap_ready "${nvme_desired}" 300
  restart_local_volume_provisioner
fi

if [[ "${workload_nodes}" -gt 0 ]]; then
  per_node="$(expected_local_ssd_pvs_per_node)"
  actual="$(count_local_ssd_pvs)"
  if [[ -n "${per_node}" ]]; then
    expected=$((workload_nodes * per_node))
    if [[ "${actual}" -ge "${expected}" ]]; then
      echo "OK  ${actual} local-ssd PVs (expected ~${expected})"
    else
      echo "FAIL ${actual}/${expected} local-ssd PVs"
      kubectl get pv -l storageclass=local-ssd 2>/dev/null || true
      fail=1
    fi
  elif [[ "${actual}" -gt 0 ]]; then
    echo "OK  ${actual} local-ssd PVs"
  else
    echo "FAIL no local-ssd PVs discovered"
    kubectl get pv -l storageclass=local-ssd 2>/dev/null || true
    fail=1
  fi
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
for s in aerospike-secret auth-secret auth-app-secret; do
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
