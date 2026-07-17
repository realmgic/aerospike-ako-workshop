#!/usr/bin/env bash
# Prepare a lab: reset (Section 1) or upgrade-lab staging (Lab 2.6).
#
# Usage:
#   ./scripts/labs/prepare-lab.sh <lab-id> [--full|--light|--skip-reset]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env

LAB_ID="${1:?Usage: prepare-lab.sh <lab-id> [--full|--light|--skip-reset]}"
shift || true

RESET_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) RESET_OVERRIDE=full ;;
    --light) RESET_OVERRIDE=light ;;
    --skip-reset) RESET_OVERRIDE=skip ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

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
  local version running phase

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

  if [[ "${fail}" -eq 0 ]]; then
    echo "Lab 2.6 starting state: PASS"
  else
    echo "Lab 2.6 starting state: FAIL"
    exit 1
  fi
}

prepare_lab_2_6() {
  trap restore_main_kubecontext EXIT

  echo "=== Prepare lab 2.6 (upgrade-lab cluster) ==="

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
  fi

  ensure_upgrade_lab_kubecontext
  validate_lab_2_6_starting_state
  echo "=== Lab 2.6 prepared ==="
}

if [[ "${LAB_ID}" == "2.6" ]]; then
  require_cmd aws
  prepare_lab_2_6
  exit 0
fi

ensure_main_kubecontext

default_reset_for_lab() {
  case "$1" in
    1.1|1.2|1.3|1.4|1.5) echo "light" ;;
    *)
      echo "ERROR: unknown lab id: $1 (expected 1.1–1.5 or 2.6)" >&2
      exit 1
      ;;
  esac
}

RESET_MODE="${RESET_OVERRIDE:-$(default_reset_for_lab "${LAB_ID}")}"

echo "=== Prepare lab ${LAB_ID} (reset=${RESET_MODE}, NODE_PROVISIONING=${NODE_PROVISIONING}) ==="

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
  1.1|1.2|1.3|1.4|1.5)
    "${SCRIPT_DIR}/lab-nodes.sh" "${LAB_ID}" ensure
    "${SCRIPT_DIR}/lab-nodes.sh" "${LAB_ID}" validate
    ;;
  *)
    echo "ERROR: unknown lab id: ${LAB_ID}" >&2
    exit 1
    ;;
esac

echo "=== Lab ${LAB_ID} prepared ==="
