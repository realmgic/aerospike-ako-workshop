#!/usr/bin/env bash
# Prepare a lab: reset (Section 1), cluster staging (Labs 2.1/2.3/2.5), or upgrade-lab (Lab 2.6).
#
# Usage:
#   ./scripts/labs/prepare-lab.sh <lab-id> [--dim|--disk] [--full|--light|--skip-reset] [--load-data]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/cluster-storage.sh"
load_env

LAB_ID="${1:?Usage: prepare-lab.sh <lab-id> [--dim|--disk] [--full|--light|--skip-reset] [--load-data]}"
shift || true

RESET_OVERRIDE=""
LOAD_DATA=false
CLI_CLUSTER_STORAGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) RESET_OVERRIDE=full ;;
    --light) RESET_OVERRIDE=light ;;
    --skip-reset) RESET_OVERRIDE=skip ;;
    --load-data) LOAD_DATA=true ;;
    --dim)
      if [[ -n "${CLI_CLUSTER_STORAGE}" && "${CLI_CLUSTER_STORAGE}" != dim ]]; then
        echo "ERROR: --dim and --disk are mutually exclusive" >&2
        exit 1
      fi
      CLI_CLUSTER_STORAGE=dim
      ;;
    --disk)
      if [[ -n "${CLI_CLUSTER_STORAGE}" && "${CLI_CLUSTER_STORAGE}" != disk ]]; then
        echo "ERROR: --dim and --disk are mutually exclusive" >&2
        exit 1
      fi
      CLI_CLUSTER_STORAGE=disk
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

export CLI_CLUSTER_STORAGE
log_cluster_storage_choice "${LAB_ID}"

SCRIPT_DIR="$(dirname "$0")"
WORKSHOP_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
UPGRADE_LAB_SETUP="${WORKSHOP_SCRIPTS}/setup/upgrade-lab/setup-upgrade-lab.sh"

restore_main_kubecontext() {
  if cluster_exists "${CLUSTER_NAME}"; then
    ensure_kubecontext "${CLUSTER_NAME}" >/dev/null 2>&1 || true
    echo "Restored kubectl context to main cluster: ${CLUSTER_NAME}"
  fi
}

validate_lab_2_6_starting_state() {
  local fail=0
  local version running phase expected_engine

  version="$(aws eks describe-cluster --name "${UPGRADE_LAB_CLUSTER_NAME}" --region "${AWS_REGION}" \
    --query 'cluster.version' --output text 2>/dev/null || echo unknown)"
  if [[ "${version}" == "${UPGRADE_LAB_K8S_VERSION_START}" ]]; then
    echo "OK  EKS version ${version}"
  else
    echo "FAIL EKS version ${version} (expected ${UPGRADE_LAB_K8S_VERSION_START})"
    fail=1
  fi

  running="$(kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${running}" -eq "${UPGRADE_LAB_AEROSPIKE_SIZE}" ]]; then
    echo "OK  ${running}/${UPGRADE_LAB_AEROSPIKE_SIZE} Aerospike pods Running"
  else
    echo "FAIL ${running}/${UPGRADE_LAB_AEROSPIKE_SIZE} Aerospike pods Running"
    fail=1
  fi

  phase="$(kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.status.phase}' 2>/dev/null || echo unknown)"
  echo "    AerospikeCluster phase: ${phase}"

  expected_engine="device"
  [[ "${EFFECTIVE_CLUSTER_STORAGE}" == dim ]] && expected_engine="memory"
  if validate_cluster_storage_engine "${expected_engine}"; then
    :
  else
    fail=1
  fi

  if [[ "${EFFECTIVE_CLUSTER_STORAGE}" == disk ]]; then
    local pvc_count
    pvc_count="$(kubectl -n "${NAMESPACE}" get pvc -l aerospike.com/cr=aerocluster --no-headers 2>/dev/null \
      | awk '$2 ~ /local-ssd/ || $6 ~ /local-ssd/ {c++} END{print c+0}')"
    if [[ "${pvc_count:-0}" -ge "${UPGRADE_LAB_AEROSPIKE_SIZE}" ]]; then
      echo "OK  ${pvc_count} local-ssd PVC(s) bound"
    else
      echo "WARN ${pvc_count}/${UPGRADE_LAB_AEROSPIKE_SIZE} local-ssd PVCs — check storage setup"
    fi
  fi

  local secret
  for secret in aerospike-secret auth-secret auth-app-secret auth-exporter-secret; do
    if kubectl -n "${NAMESPACE}" get secret "${secret}" >/dev/null 2>&1; then
      echo "OK  secret ${secret}"
    else
      echo "FAIL secret ${secret} missing on upgrade-lab"
      fail=1
    fi
  done

  if [[ "${fail}" -eq 0 ]]; then
    echo "Lab 2.6 starting state: PASS"
  else
    echo "Lab 2.6 starting state: FAIL"
    exit 1
  fi
}

prepare_lab_2_6() {
  trap restore_main_kubecontext EXIT

  echo "=== Prepare lab 2.6 (upgrade-lab cluster, storage=${EFFECTIVE_CLUSTER_STORAGE}) ==="

  if ! cluster_exists "${UPGRADE_LAB_CLUSTER_NAME}"; then
    if [[ "${RESET_OVERRIDE}" == "skip" ]]; then
      echo "ERROR: upgrade-lab cluster ${UPGRADE_LAB_CLUSTER_NAME} not found" >&2
      exit 1
    fi
    echo "Upgrade-lab cluster not found — running setup..."
    "${UPGRADE_LAB_SETUP}"
  else
    ensure_upgrade_lab_kubecontext
    echo "Upgrade-lab cluster ${UPGRADE_LAB_CLUSTER_NAME} already exists"
    if [[ "${RESET_OVERRIDE}" != "skip" ]]; then
      expected_engine="device"
      [[ "${EFFECTIVE_CLUSTER_STORAGE}" == dim ]] && expected_engine="memory"
      missing_secrets=false
      for secret in aerospike-secret auth-secret auth-app-secret auth-exporter-secret; do
        if ! kubectl -n "${NAMESPACE}" get secret "${secret}" >/dev/null 2>&1; then
          missing_secrets=true
          break
        fi
      done
      if [[ "${missing_secrets}" == true ]]; then
        echo "Upgrade-lab secrets missing — re-running post-bootstrap..."
        "${WORKSHOP_SCRIPTS}/setup/upgrade-lab/setup-upgrade-lab-post-bootstrap.sh"
      elif kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
        actual="$(cluster_storage_engine_type)"
        if [[ "${actual}" != "${expected_engine}" ]]; then
          echo "Storage mismatch (${actual} vs ${expected_engine}) — re-running post-bootstrap..."
          "${WORKSHOP_SCRIPTS}/setup/upgrade-lab/setup-upgrade-lab-post-bootstrap.sh"
        fi
      else
        "${WORKSHOP_SCRIPTS}/setup/upgrade-lab/setup-upgrade-lab-post-bootstrap.sh"
      fi
    fi
  fi

  ensure_upgrade_lab_kubecontext
  validate_lab_2_6_starting_state
  echo "=== Lab 2.6 prepared ==="
}

deploy_cluster() {
  if [[ "${DEPLOY_PATH}" == "helm" ]]; then
    "${SCRIPT_DIR}/deploy-cluster-helm.sh"
  else
    "${SCRIPT_DIR}/deploy-cluster.sh"
  fi
}

validate_cluster() {
  local phase running expected=3
  phase="$(kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.status.phase}' 2>/dev/null || echo missing)"
  running="$(kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"

  if [[ "${phase}" == "Completed" ]] && [[ "${running:-0}" -ge "${expected}" ]]; then
    echo "OK  cluster Ready (${running}/${expected} pods, phase ${phase}, storage=${EFFECTIVE_CLUSTER_STORAGE})"
    return 0
  fi

  echo "FAIL cluster not ready (phase=${phase}, ${running}/${expected} pods Running)" >&2
  kubectl -n "${NAMESPACE}" get aerospikecluster,pods 2>/dev/null || true
  return 1
}

validate_baseline_image() {
  local image
  : "${AEROSPIKE_IMAGE:=aerospike/aerospike-server-enterprise:8.1.0.0}"
  image="$(kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.spec.image}' 2>/dev/null || echo missing)"
  if [[ "${image}" == "${AEROSPIKE_IMAGE}" ]] || [[ "${image}" == *"8.1.0"* ]]; then
    echo "OK  baseline image (${image})"
    return 0
  fi
  echo "FAIL expected 8.1.0.x baseline image (got ${image}) — re-run without --skip-reset" >&2
  return 1
}

validate_maintenance_image() {
  local image
  image="$(kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster -o jsonpath='{.spec.image}' 2>/dev/null || echo missing)"
  if [[ "${image}" == *"8.1.2"* ]]; then
    echo "OK  maintenance image (${image})"
    return 0
  fi
  echo "FAIL expected 8.1.2.x image (got ${image}) — complete Lab 2.3 first" >&2
  return 1
}

deploy_maintenance_cluster() {
  if [[ "${DEPLOY_PATH}" == "helm" ]]; then
    "${SCRIPT_DIR}/deploy-cluster-maintenance-helm.sh"
  else
    "${SCRIPT_DIR}/deploy-cluster-maintenance.sh"
  fi
}

wait_for_cluster() {
  kubectl -n "${NAMESPACE}" wait --for=jsonpath='{.status.phase}'=Completed \
    aerospikecluster/aerocluster --timeout=600s
  validate_cluster
}

prepare_cluster_lab() {
  local lab_id="$1"
  local reason="$2"
  local check_baseline_image="${3:-false}"
  local reset_mode="${RESET_OVERRIDE:-light}"

  echo "=== Prepare lab ${lab_id} (reset=${reset_mode}, storage=${EFFECTIVE_CLUSTER_STORAGE}, DEPLOY_PATH=${DEPLOY_PATH}) ==="
  echo "${reason}"

  ensure_main_kubecontext

  case "${reset_mode}" in
    full)
      echo "Running full reset (database + workload nodes)..."
      "${WORKSHOP_SCRIPTS}/reset-cluster.sh" --yes
      ;;
    light)
      echo "Running light reset (delete AerospikeCluster aerocluster)..."
      "${WORKSHOP_SCRIPTS}/labs/teardown-cluster.sh"
      ;;
    skip)
      echo "Skipping teardown (validating existing cluster)"
      validate_cluster
      expected_engine="device"
      [[ "${EFFECTIVE_CLUSTER_STORAGE}" == dim ]] && expected_engine="memory"
      validate_cluster_storage_engine "${expected_engine}"
      if [[ "${check_baseline_image}" == true ]]; then
        validate_baseline_image
      fi
      echo "=== Lab ${lab_id} prepared ==="
      return 0
      ;;
  esac

  if [[ "${EFFECTIVE_CLUSTER_STORAGE}" == disk ]]; then
    validate_baseline_local_ssd_pvs 3
  fi

  deploy_cluster
  validate_cluster
  expected_engine="device"
  [[ "${EFFECTIVE_CLUSTER_STORAGE}" == dim ]] && expected_engine="memory"
  validate_cluster_storage_engine "${expected_engine}"
  if [[ "${check_baseline_image}" == true ]]; then
    validate_baseline_image
  fi
  echo "=== Lab ${lab_id} prepared ==="
}

prepare_lab_2_1() {
  prepare_cluster_lab "2.1" \
    "Tearing down prior aerocluster (Section 1 rack/cluster CR uses the same name) and deploying baseline cluster." \
    false
}

prepare_lab_2_3() {
  prepare_cluster_lab "2.3" \
    "Resetting to baseline on 8.1.0.x (e.g. after Lab 1.4 RF=3 or a prior 2.3 attempt)." \
    true
}

prepare_lab_2_5() {
  local reset_mode="${RESET_OVERRIDE:-}"

  echo "=== Prepare lab 2.5 (reset=${reset_mode:-deploy}, storage=${EFFECTIVE_CLUSTER_STORAGE}, DEPLOY_PATH=${DEPLOY_PATH}, load_data=${LOAD_DATA}) ==="
  echo "Deploying maintenance baseline (8.1.2.x) for node maintenance lab."

  ensure_main_kubecontext

  if [[ "${reset_mode}" == "skip" ]]; then
    if ! kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
      echo "ERROR: aerocluster not found — run without --skip-reset first" >&2
      exit 1
    fi
    validate_maintenance_image
    expected_engine="device"
    [[ "${EFFECTIVE_CLUSTER_STORAGE}" == dim ]] && expected_engine="memory"
    validate_cluster_storage_engine "${expected_engine}"
    validate_cluster
    echo "=== Lab 2.5 prepared (validate-only) ==="
    return 0
  fi

  case "${reset_mode}" in
    full)
      echo "Running full reset (database + workload nodes)..."
      "${WORKSHOP_SCRIPTS}/reset-cluster.sh" --yes
      echo "ERROR: Lab 2.5 full reset removes cluster state — complete Labs 2.1–2.4 first" >&2
      exit 1
      ;;
    light)
      echo "NOTE: --light behaves like default for Lab 2.5 (teardown + redeploy)"
      ;;
  esac

  if kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
    echo "Removing existing aerocluster..."
    "${WORKSHOP_SCRIPTS}/labs/teardown-cluster.sh"
    wait_for_cluster_gone 300
  fi

  if [[ "${EFFECTIVE_CLUSTER_STORAGE}" == disk ]]; then
    validate_baseline_local_ssd_pvs 3
  fi

  deploy_maintenance_cluster
  wait_for_cluster
  expected_engine="device"
  [[ "${EFFECTIVE_CLUSTER_STORAGE}" == dim ]] && expected_engine="memory"
  validate_cluster_storage_engine "${expected_engine}"

  if [[ "${LOAD_DATA}" == true ]]; then
    "${SCRIPT_DIR}/load-data.sh"
  fi

  echo "=== Lab 2.5 prepared ==="
}

if [[ "${LAB_ID}" == "2.6" ]]; then
  require_cmd aws
  prepare_lab_2_6
  exit 0
fi

if [[ "${LAB_ID}" == "2.1" ]]; then
  prepare_lab_2_1
  exit 0
fi

if [[ "${LAB_ID}" == "2.3" ]]; then
  prepare_lab_2_3
  exit 0
fi

if [[ "${LAB_ID}" == "2.5" ]]; then
  prepare_lab_2_5
  exit 0
fi

ensure_main_kubecontext

default_reset_for_lab() {
  case "$1" in
    1.1|1.2|1.3|1.4) echo "light" ;;
    *)
      echo "ERROR: unknown lab id: $1 (expected 1.1–1.4, 2.1, 2.3, 2.5, or 2.6)" >&2
      exit 1
      ;;
  esac
}

RESET_MODE="${RESET_OVERRIDE:-$(default_reset_for_lab "${LAB_ID}")}"

echo "=== Prepare lab ${LAB_ID} (reset=${RESET_MODE}, storage=${EFFECTIVE_CLUSTER_STORAGE}, NODE_PROVISIONING=${NODE_PROVISIONING}) ==="

case "${RESET_MODE}" in
  full)
    echo "Running full reset (database + workload nodes)..."
    "${WORKSHOP_SCRIPTS}/reset-cluster.sh" --yes
    ;;
  light)
    echo "Running light reset (database only)..."
    "${WORKSHOP_SCRIPTS}/labs/teardown-cluster.sh"
    ;;
  skip)
    echo "Skipping reset (continuing from prior lab state)"
    ;;
esac

case "${LAB_ID}" in
  1.1|1.2|1.3|1.4)
    "${SCRIPT_DIR}/lab-nodes.sh" "${LAB_ID}" ensure
    "${SCRIPT_DIR}/lab-nodes.sh" "${LAB_ID}" validate
    ;;
  *)
    echo "ERROR: unknown lab id: ${LAB_ID}" >&2
    exit 1
    ;;
esac

echo "=== Lab ${LAB_ID} prepared ==="
