#!/usr/bin/env bash
# Shared helpers for workshop scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

load_env() {
  local env_file="${WORKSHOP_ROOT}/scripts/env/workshop.env"
  if [[ -f "${env_file}" ]]; then
    # shellcheck disable=SC1090
    source "${env_file}"
  else
    # shellcheck disable=SC1090
    source "${WORKSHOP_ROOT}/scripts/env/workshop.env.example"
    echo "Note: using workshop.env.example — copy to workshop.env for production runs" >&2
  fi
  : "${CLUSTER_NAME:=my-cluster}"
  : "${AWS_REGION:=us-east-1}"
  : "${NAMESPACE:=aerospike}"
  : "${OPERATOR_NAMESPACE:=operators}"
  : "${OPERATOR_REPO:=aerospike-kubernetes-operator}"
  : "${DEPLOY_PATH:=olm}"
  : "${NODE_PROVISIONING:=eksctl}"
  : "${KARPENTER_VERSION:=1.1.1}"
  : "${KARPENTER_NAMESPACE:=karpenter}"
  : "${KARPENTER_CONSOLIDATION:=WhenEmpty}"
  : "${KARPENTER_SYSTEM_NODEGROUP:=ng-system}"
  : "${KARPENTER_SYSTEM_NODE_TYPE:=t3.large}"
  : "${KARPENTER_SYSTEM_NODE_COUNT:=2}"
  : "${KARPENTER_NODEPOOL_NAME:=aerospike-i8g}"
  : "${KARPENTER_NODEPOOL_VERTICAL_NAME:=aerospike-i8g-4xl}"
  : "${KARPENTER_NODECLASS_NAME:=aerospike-i8g}"
  : "${NVME_DISK_LAYOUT:=}"
  : "${NODE_TYPE_VERTICAL:=i8g.4xlarge}"
  : "${NODEGROUP_NAME:=ng-aerospike}"
  : "${NODEGROUP_NAME_VERTICAL:=ng-aerospike-4xl}"
  : "${AWS_ZONES:=us-east-1c,us-east-1d}"
  : "${MIN_NODES_PER_ZONE:=2}"
  : "${UPGRADE_LAB_CLUSTER_NAME:=my-cluster-k8s-upgrade}"
  : "${UPGRADE_LAB_NODEGROUP_NAME:=ng-upgrade-lab}"
  : "${UPGRADE_LAB_K8S_VERSION_START:=1.31}"
  : "${UPGRADE_LAB_K8S_VERSION_TARGET:=1.32}"
  : "${UPGRADE_LAB_NODE_COUNT:=3}"
  : "${UPGRADE_LAB_NODE_TYPE:=i8g.2xlarge}"
  : "${UPGRADE_LAB_AEROSPIKE_SIZE:=3}"
  : "${FEATURES_CONF_PATH:=secrets/features.conf}"

  IFS=',' read -r NODE_ZONE_A NODE_ZONE_B _ <<< "${AWS_ZONES},,"
  export NODE_ZONE_A NODE_ZONE_B
}

features_conf_path() {
  load_env
  local path="${FEATURES_CONF_PATH}"
  if [[ "${path}" != /* ]]; then
    path="${WORKSHOP_ROOT}/${path}"
  fi
  echo "${path}"
}

vendor_storage_dir() {
  echo "${WORKSHOP_ROOT}/vendor/storage"
}

operator_repo_path() {
  load_env
  if [[ -d "${WORKSHOP_ROOT}/.vendor/${OPERATOR_REPO}" ]]; then
    echo "${WORKSHOP_ROOT}/.vendor/${OPERATOR_REPO}"
  else
    echo "${WORKSHOP_ROOT}/.vendor/${OPERATOR_REPO}"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: required command not found: $1" >&2; exit 1; }
}

cluster_exists() {
  local name="$1"
  eksctl get cluster --name "${name}" --region "${AWS_REGION}" >/dev/null 2>&1
}

workshop_kubeconfig_dir() {
  load_env
  local dir="${WORKSHOP_ROOT}/.kube"
  mkdir -p "${dir}"
  echo "${dir}"
}

kubeconfig_path_for_cluster() {
  local cluster_name="$1"
  echo "$(workshop_kubeconfig_dir)/${cluster_name}.yaml"
}

default_kubeconfig_path() {
  echo "${KUBECONFIG:-${HOME}/.kube/config}"
}

apply_workshop_kubeconfig() {
  if [[ -n "${WORKSHOP_KUBECONFIG:-}" ]]; then
    mkdir -p "$(dirname "${WORKSHOP_KUBECONFIG}")"
    export KUBECONFIG="${WORKSHOP_KUBECONFIG}"
  fi
}

merge_kubeconfig_into_default() {
  local src="$1"
  local dest
  dest="$(default_kubeconfig_path)"

  if [[ ! -f "${src}" ]]; then
    return 0
  fi

  require_cmd kubectl
  mkdir -p "$(dirname "${dest}")"
  if [[ ! -f "${dest}" ]]; then
    cp "${src}" "${dest}"
    echo "Merged kubeconfig: ${src} → ${dest}"
    return 0
  fi

  local merged="${dest}.merged.$$"
  KUBECONFIG="${dest}:${src}" kubectl config view --flatten > "${merged}"
  mv "${merged}" "${dest}"
  echo "Merged kubeconfig: ${src} → ${dest}"
}

cleanup_workshop_kubeconfig_files() {
  local dir
  dir="$(workshop_kubeconfig_dir 2>/dev/null || true)"
  if [[ -n "${dir}" && -d "${dir}" ]]; then
    rm -f "${dir}"/*.yaml 2>/dev/null || true
    echo "Removed isolated kubeconfig files under ${dir}"
  fi
}

with_kubeconfig() {
  local kc="$1"
  shift
  (
    export KUBECONFIG="${kc}"
    "$@"
  )
}

run_with_log_prefix() {
  local prefix="$1"
  shift
  "$@" 2>&1 | sed "s/^/${prefix} /"
}

current_kube_cluster() {
  kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || true
}

current_kube_context() {
  kubectl config current-context 2>/dev/null || true
}

ensure_kubecontext() {
  local cluster_name="$1"
  require_cmd aws
  require_cmd kubectl

  if ! cluster_exists "${cluster_name}"; then
    echo "ERROR: EKS cluster '${cluster_name}' not found in ${AWS_REGION}" >&2
    echo "Create it first or check UPGRADE_LAB_CLUSTER_NAME / CLUSTER_NAME in workshop.env" >&2
    exit 1
  fi

  if [[ -n "${KUBECONFIG:-}" ]]; then
    aws eks update-kubeconfig --name "${cluster_name}" --region "${AWS_REGION}" --kubeconfig "${KUBECONFIG}" >/dev/null
  else
    aws eks update-kubeconfig --name "${cluster_name}" --region "${AWS_REGION}" >/dev/null
  fi
  echo "kubectl context: $(current_kube_context) (cluster: $(current_kube_cluster))"
}

assert_kubecontext() {
  local expected_cluster="$1"
  local current_cluster
  current_cluster="$(current_kube_cluster)"

  if [[ "${current_cluster}" != *"${expected_cluster}"* ]]; then
    echo "ERROR: kubectl is not targeting '${expected_cluster}' (current cluster: ${current_cluster:-unknown})" >&2
    echo "Run: aws eks update-kubeconfig --name ${expected_cluster} --region ${AWS_REGION}" >&2
    exit 1
  fi
}

ensure_main_kubecontext() {
  load_env
  ensure_kubecontext "${CLUSTER_NAME}"
  assert_kubecontext "${CLUSTER_NAME}"
}

ensure_upgrade_lab_kubecontext() {
  load_env
  ensure_kubecontext "${UPGRADE_LAB_CLUSTER_NAME}"
  assert_kubecontext "${UPGRADE_LAB_CLUSTER_NAME}"
}

ensure_target_kubecontext() {
  load_env
  if [[ "${CLUSTER_NAME}" == "${UPGRADE_LAB_CLUSTER_NAME}" ]]; then
    ensure_upgrade_lab_kubecontext
  else
    ensure_main_kubecontext
  fi
}

delete_kubecontext_for_cluster() {
  local cluster_name="$1"
  local ctx
  while IFS= read -r ctx; do
    [[ -z "${ctx}" ]] && continue
    if [[ "${ctx}" == *"${cluster_name}"* ]]; then
      kubectl config delete-context "${ctx}" >/dev/null 2>&1 || true
      echo "Removed kubeconfig context: ${ctx}"
    fi
  done < <(kubectl config get-contexts -o name 2>/dev/null || true)
}
