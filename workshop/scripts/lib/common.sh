#!/usr/bin/env bash
# Shared helpers for workshop scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

load_env() {
  # Preserve CLUSTER_NAME when a wrapper targets upgrade-lab (or another cluster)
  # before re-sourcing workshop.env — otherwise shared scripts hit the main cluster.
  local preserve_cluster="${CLUSTER_NAME:-}"
  local env_file="${WORKSHOP_ROOT}/scripts/env/workshop.env"
  if [[ -f "${env_file}" ]]; then
    # shellcheck disable=SC1090
    source "${env_file}"
  else
    # shellcheck disable=SC1090
    source "${WORKSHOP_ROOT}/scripts/env/workshop.env.example"
    echo "Note: using workshop.env.example — copy to workshop.env for production runs" >&2
  fi
  if [[ -n "${preserve_cluster}" ]]; then
    CLUSTER_NAME="${preserve_cluster}"
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
  case "${KARPENTER_CONSOLIDATION}" in
    Off|WhenEmpty|WhenEmptyOrUnderutilized) ;;
    *)
      echo "ERROR: KARPENTER_CONSOLIDATION must be Off, WhenEmpty, or WhenEmptyOrUnderutilized (got: ${KARPENTER_CONSOLIDATION})" >&2
      exit 1
      ;;
  esac
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
  : "${CLUSTER_STORAGE:=disk}"
  : "${CLUSTER_STORAGE_DIM_LABS:=}"
  : "${CLUSTER_STORAGE_DISK_LABS:=}"
  : "${FEATURES_CONF_PATH:=secrets/features.conf}"
  : "${HELM_OPERATOR_RELEASE:=aerospike-kubernetes-operator}"
  : "${HELM_CLUSTER_RELEASE:=aerocluster}"
  : "${AKO_VERSION_START:=4.2.0}"
  : "${AKO_CLUSTER_CHART_VERSION:=}"

  IFS=',' read -r NODE_ZONE_A NODE_ZONE_B _ <<< "${AWS_ZONES},,"
  export NODE_ZONE_A NODE_ZONE_B
}

# OLM installs deployment/aerospike-operator-controller-manager; Helm uses release name.
ako_operator_deployment_name() {
  if [[ "${DEPLOY_PATH}" == "helm" ]]; then
    echo "${HELM_OPERATOR_RELEASE}"
  else
    echo "aerospike-operator-controller-manager"
  fi
}

# Parse semver from aerospike-kubernetes-operator.v4.4.1 or chart name suffix.
_ako_version_from_csv_name() {
  local csv_name="$1"
  if [[ "${csv_name}" =~ ^aerospike-kubernetes-operator\.v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Parse semver from aerospike-kubernetes-operator-4.4.1 Helm chart string.
_ako_version_from_helm_chart() {
  local chart="$1"
  if [[ "${chart}" =~ aerospike-kubernetes-operator-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Return installed AKO operator version (e.g. 4.4.1), or empty if unknown.
installed_ako_version() {
  local version="" chart="" csv="" installed=""
  if [[ "${DEPLOY_PATH:-olm}" == "helm" ]]; then
    if command -v helm >/dev/null 2>&1; then
      if command -v jq >/dev/null 2>&1; then
        chart="$(helm list -n "${OPERATOR_NAMESPACE}" -o json 2>/dev/null \
          | jq -r --arg n "${HELM_OPERATOR_RELEASE}" '.[] | select(.name==$n) | .chart // empty' 2>/dev/null || true)"
      else
        chart="$(helm list -n "${OPERATOR_NAMESPACE}" 2>/dev/null \
          | awk -v rel="${HELM_OPERATOR_RELEASE}" '$1 == rel { print $NF }' | head -1)"
      fi
      version="$(_ako_version_from_helm_chart "${chart}")"
    fi
  else
    installed="$(kubectl get subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" \
      -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    version="$(_ako_version_from_csv_name "${installed}")"
    if [[ -z "${version}" && -n "${installed}" ]]; then
      version="$(kubectl get csv "${installed}" -n "${OPERATOR_NAMESPACE}" \
        -o jsonpath='{.spec.version}' 2>/dev/null || true)"
    fi
  fi
  echo "${version}"
}

# aerospike-cluster chart --version: override, then installed operator, then install pin.
resolve_cluster_helm_chart_version() {
  if [[ -n "${AKO_CLUSTER_CHART_VERSION:-}" ]]; then
    echo "${AKO_CLUSTER_CHART_VERSION}"
    return 0
  fi
  local installed
  installed="$(installed_ako_version)"
  if [[ -n "${installed}" ]]; then
    echo "${installed}"
    return 0
  fi
  echo "Note: could not detect installed AKO — using AKO_VERSION_START (${AKO_VERSION_START}) for cluster chart" >&2
  echo "${AKO_VERSION_START}"
}

# Fail if installed AKO is below minimum (semver compare via sort -V).
validate_ako_min_version() {
  local min_version="$1" installed=""
  installed="$(installed_ako_version)"
  if [[ -z "${installed}" ]]; then
    echo "ERROR: could not detect installed AKO version (complete Lab 0.3 / 2.2 first)" >&2
    return 1
  fi
  if [[ "$(printf '%s\n' "${min_version}" "${installed}" | sort -V | head -1)" == "${min_version}" ]]; then
    echo "OK  AKO ${installed} (required >= ${min_version})"
    return 0
  fi
  echo "ERROR: AKO ${installed} is below required ${min_version} — complete Lab 2.2 upgrade ladder first" >&2
  return 1
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
