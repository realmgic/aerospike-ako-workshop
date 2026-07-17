#!/usr/bin/env bash
# Ensure or validate workload nodes for Section 1 labs.
#
# Usage:
#   ./scripts/labs/lab-nodes.sh <lab> ensure|validate [options]
#
# Options:
#   --scale-up     Lab 1.1: scale workload pool to 5 nodes (eksctl) or trigger scale (karpenter)
#   --vertical     Lab 1.3/1.4: add 4xl pool alongside existing 2xl (mid-lab vertical scale)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/zone-check.sh"
source "$(dirname "$0")/../lib/local-storage.sh"
source "$(dirname "$0")/../lib/nodepool-zones.sh"
load_env
ensure_main_kubecontext

LAB_ID="${1:?Usage: lab-nodes.sh <lab-id> ensure|validate [--scale-up|--vertical]}"
ACTION="${2:?Usage: lab-nodes.sh <lab-id> ensure|validate [--scale-up|--vertical]}"
shift 2 || true

SCALE_UP=false
VERTICAL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scale-up) SCALE_UP=true ;;
    --vertical) VERTICAL=true ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

require_cmd kubectl
require_cmd eksctl

KARPENTER_DIR="${WORKSHOP_ROOT}/scripts/setup/karpenter"
NODE_WAIT_TIMEOUT=900
NVME_WAIT_TIMEOUT=1800

count_baseline_nodes_ready() {
  kubectl get nodes -l "workshop.aerospike.com/node-pool=baseline,node.kubernetes.io/instance-type=${NODE_TYPE}" \
    --no-headers 2>/dev/null | grep -c ' Ready ' || true
}

count_2xl_nodes_ready() {
  count_baseline_nodes_ready
}

count_4xl_nodes_ready() {
  kubectl get nodes -l "workshop.aerospike.com/node-pool=vertical,node.kubernetes.io/instance-type=${NODE_TYPE_VERTICAL}" \
    --no-headers 2>/dev/null | grep -c ' Ready ' || true
}

count_workload_nodes_ready() {
  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    kubectl get nodes -l 'workshop.aerospike.com/workload=aerospike' --no-headers 2>/dev/null \
      | grep -c ' Ready ' || true
  else
    local ready_2xl ready_4xl
    ready_2xl="$(count_2xl_nodes_ready)"
    ready_4xl="$(count_4xl_nodes_ready)"
    echo $((ready_2xl + ready_4xl))
  fi
}

count_nodes_instance_type() {
  local instance_type="$1"
  kubectl get nodes -l "node.kubernetes.io/instance-type=${instance_type}" --no-headers 2>/dev/null \
    | grep -c ' Ready ' || true
}

eksctl_nodegroup_exists() {
  local name="$1"
  eksctl get nodegroup --cluster="${CLUSTER_NAME}" --region="${AWS_REGION}" --name="${name}" >/dev/null 2>&1
}

wait_2xl_nodes() {
  local expected="$1"
  local deadline=$((SECONDS + NODE_WAIT_TIMEOUT))
  while true; do
    local ready
    ready="$(count_2xl_nodes_ready)"
    echo "  2xl nodes Ready: ${ready}/${expected}"
    if [[ "${ready}" -ge "${expected}" ]]; then
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      echo "ERROR: timed out waiting for ${expected}× ${NODE_TYPE} nodes" >&2
      kubectl get nodes -o wide
      exit 1
    fi
    sleep 15
  done
}

wait_4xl_nodes() {
  local expected="$1"
  local deadline=$((SECONDS + NODE_WAIT_TIMEOUT))
  while true; do
    local ready
    ready="$(count_4xl_nodes_ready)"
    echo "  4xl nodes Ready: ${ready}/${expected}"
    if [[ "${ready}" -ge "${expected}" ]]; then
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      echo "ERROR: timed out waiting for ${expected}× ${NODE_TYPE_VERTICAL} nodes" >&2
      kubectl get nodes -o wide
      exit 1
    fi
    sleep 15
  done
}

drain_excess_nodes_by_instance_type() {
  local instance_type="$1"
  local target="$2"
  local ready
  ready="$(count_nodes_instance_type "${instance_type}")"
  while [[ "${ready}" -gt "${target}" ]]; do
    local excess=$((ready - target))
    echo "Draining ${excess} excess ${instance_type} node(s) (${ready} > ${target})..."
    while IFS= read -r node; do
      [[ -z "${node}" ]] && continue
      kubectl cordon "${node}"
      kubectl drain "${node}" --ignore-daemonsets --delete-emptydir-data --force --grace-period=120
    done < <(
      kubectl get nodes -l "node.kubernetes.io/instance-type=${instance_type}" \
        --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -n "${excess}"
    )
    ready="$(count_nodes_instance_type "${instance_type}")"
  done
}

wait_eksctl_nodegroup_ready() {
  local ng_name="$1"
  local expected="$2"
  local deadline=$((SECONDS + NODE_WAIT_TIMEOUT))
  while true; do
    local ready
    ready="$(kubectl get nodes -l "alpha.eksctl.io/nodegroup-name=${ng_name}" --no-headers 2>/dev/null \
      | grep -c ' Ready ' || true)"
    echo "  ${ng_name} nodes Ready: ${ready}/${expected}"
    if [[ "${ready}" -ge "${expected}" ]]; then
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      echo "ERROR: timed out waiting for nodegroup ${ng_name}" >&2
      kubectl get nodes -o wide
      exit 1
    fi
    sleep 15
  done
}

label_eksctl_nodegroup_pool() {
  local ng_name="$1"
  local pool_label="$2"
  echo "Labeling nodegroup ${ng_name} nodes: workshop.aerospike.com/node-pool=${pool_label}"
  kubectl get nodes -l "alpha.eksctl.io/nodegroup-name=${ng_name}" -o name 2>/dev/null \
    | while read -r node; do
        kubectl label "${node}" "workshop.aerospike.com/node-pool=${pool_label}" --overwrite
      done
}

ensure_eksctl_nodegroup_in_zone() {
  local name="$1"
  local node_type="$2"
  local zone="$3"
  local count="$4"
  local pool_label="${5:-}"

  if eksctl_nodegroup_exists "${name}"; then
    echo "Nodegroup ${name} exists — scaling to ${count}..."
    eksctl scale nodegroup \
      --cluster="${CLUSTER_NAME}" \
      --region="${AWS_REGION}" \
      --name="${name}" \
      --nodes="${count}"
  else
    local create_args=(
      --cluster "${CLUSTER_NAME}"
      --region "${AWS_REGION}"
      --node-zones "${zone}"
      --name "${name}"
      --node-type "${node_type}"
      --nodes "${count}"
      --nodes-min 1
      --nodes-max 8
      --ssh-access
      --ssh-public-key "${SSH_PUBLIC_KEY}"
    )
    if [[ -n "${pool_label}" ]]; then
      create_args+=(--node-labels "workshop.aerospike.com/node-pool=${pool_label}")
    fi
    echo "Creating nodegroup ${name} (${node_type} × ${count} in ${zone})..."
    eksctl create nodegroup "${create_args[@]}"
  fi
  wait_eksctl_nodegroup_ready "${name}" "${count}"
  if [[ -n "${pool_label}" ]]; then
    label_eksctl_nodegroup_pool "${name}" "${pool_label}"
  fi
}

ensure_eksctl_pools_per_zone() {
  local base_name="$1"
  local node_type="$2"
  local total_count="$3"
  local pool_label="${4:-}"

  read_aws_zones_array
  local num_zones="${#AWS_ZONES_ARRAY[@]}"
  local zone idx=0 ng_name count pid
  local -a pids=()

  for zone in "${AWS_ZONES_ARRAY[@]}"; do
    [[ -z "${zone}" ]] && continue
    ng_name="$(pool_name_for_zone "${base_name}" "${zone}")"
    count="$(nodes_for_zone "${total_count}" "${idx}" "${num_zones}")"
    if eksctl_nodegroup_exists "${ng_name}"; then
      ensure_eksctl_nodegroup_in_zone "${ng_name}" "${node_type}" "${zone}" "${count}" "${pool_label}"
    else
      ( ensure_eksctl_nodegroup_in_zone "${ng_name}" "${node_type}" "${zone}" "${count}" "${pool_label}" ) &
      pids+=($!)
    fi
    idx=$((idx + 1))
  done
  if ((${#pids[@]} > 0)); then
    for pid in "${pids[@]}"; do
      wait "${pid}"
    done
  fi
}

karpenter_consolidation_exports() {
  local consolidate_after="30m"
  if [[ "${KARPENTER_CONSOLIDATION}" == "Off" ]]; then
    export KARPENTER_CONSOLIDATION="WhenEmpty"
    consolidate_after="720h"
  fi
  echo "${consolidate_after}"
}

apply_karpenter_ec2nodeclass() {
  require_cmd envsubst
  export CLUSTER_NAME AWS_REGION KARPENTER_NODECLASS_NAME
  export KARPENTER_NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
  echo "Applying Karpenter EC2NodeClass ${KARPENTER_NODECLASS_NAME}..."
  envsubst < "${KARPENTER_DIR}/01-ec2nodeclass-i8g.yaml" | kubectl apply -f -
}

apply_karpenter_nodepool_in_zone() {
  local zone="$1"
  local vertical="${2:-false}"
  local consolidate_after="$3"

  require_cmd envsubst
  export CLUSTER_NAME AWS_REGION KARPENTER_CONSOLIDATION KARPENTER_NODECLASS_NAME
  export KARPENTER_NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
  export NODE_ZONE="${zone}"

  local base_name template
  if [[ "${vertical}" == true ]]; then
    base_name="${KARPENTER_NODEPOOL_VERTICAL_NAME}"
    export NODE_TYPE_VERTICAL
    template="${KARPENTER_DIR}/02-nodepool-aerospike-vertical-zone.yaml"
  else
    base_name="${KARPENTER_NODEPOOL_NAME}"
    export NODE_TYPE
    template="${KARPENTER_DIR}/02-nodepool-aerospike-zone.yaml"
  fi
  export KARPENTER_NODEPOOL_ZONE_NAME
  KARPENTER_NODEPOOL_ZONE_NAME="$(pool_name_for_zone "${base_name}" "${zone}")"

  echo "Applying NodePool ${KARPENTER_NODEPOOL_ZONE_NAME} (zone ${zone})..."
  envsubst '${KARPENTER_NODEPOOL_ZONE_NAME} ${NODE_ZONE} ${NODE_TYPE} ${NODE_TYPE_VERTICAL} ${KARPENTER_NODECLASS_NAME} ${KARPENTER_CONSOLIDATION}' \
    < "${template}" | kubectl apply -f -
  kubectl patch nodepool "${KARPENTER_NODEPOOL_ZONE_NAME}" --type=merge \
    -p "{\"spec\":{\"disruption\":{\"consolidateAfter\":\"${consolidate_after}\"}}}" 2>/dev/null || true
}

apply_karpenter_pools_per_zone() {
  local vertical="${1:-false}"
  local consolidate_after
  consolidate_after="$(karpenter_consolidation_exports)"

  read_aws_zones_array
  local zone pid
  local -a pids=()
  for zone in "${AWS_ZONES_ARRAY[@]}"; do
    [[ -z "${zone}" ]] && continue
    ( apply_karpenter_nodepool_in_zone "${zone}" "${vertical}" "${consolidate_after}" ) &
    pids+=($!)
  done
  if ((${#pids[@]} > 0)); then
    for pid in "${pids[@]}"; do
      wait "${pid}"
    done
  fi
}

karpenter_bootstrap_deployment_name() {
  local prefix="$1"
  local zone="$2"
  echo "${prefix}-$(zone_resource_suffix "${zone}")"
}

delete_karpenter_bootstrap_deployments() {
  local prefix="$1"
  read_aws_zones_array
  local zone name
  for zone in "${AWS_ZONES_ARRAY[@]}"; do
    [[ -z "${zone}" ]] && continue
    name="$(karpenter_bootstrap_deployment_name "${prefix}" "${zone}")"
    kubectl delete deployment "${name}" -n kube-system --ignore-not-found
  done
}

bootstrap_karpenter_pool_per_zone() {
  local instance_type="$1"
  local total_count="$2"
  local deployment_prefix="$3"
  local wait_fn="$4"

  read_aws_zones_array
  local num_zones="${#AWS_ZONES_ARRAY[@]}"
  local zone idx=0 replicas dep_name app_label

  app_label="${deployment_prefix}"
  for zone in "${AWS_ZONES_ARRAY[@]}"; do
    [[ -z "${zone}" ]] && continue
    replicas="$(nodes_for_zone "${total_count}" "${idx}" "${num_zones}")"
    dep_name="$(karpenter_bootstrap_deployment_name "${deployment_prefix}" "${zone}")"
    echo "Bootstrap ${dep_name}: ${replicas} pod(s) in ${zone} (${instance_type})..."
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${dep_name}
  namespace: kube-system
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: ${app_label}
      workshop.aerospike.com/zone: $(zone_resource_suffix "${zone}")
  template:
    metadata:
      labels:
        app: ${app_label}
        workshop.aerospike.com/zone: $(zone_resource_suffix "${zone}")
    spec:
      nodeSelector:
        node.kubernetes.io/instance-type: ${instance_type}
      tolerations:
        - operator: Exists
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: topology.kubernetes.io/zone
                    operator: In
                    values:
                      - ${zone}
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: ${app_label}
                  workshop.aerospike.com/zone: $(zone_resource_suffix "${zone}")
              topologyKey: kubernetes.io/hostname
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
EOF
    idx=$((idx + 1))
  done

  "${wait_fn}" "${total_count}"
  delete_karpenter_bootstrap_deployments "${deployment_prefix}"
}

scale_karpenter_pool_to_count() {
  local instance_type="$1"
  local target="$2"
  local deployment_prefix="$3"
  local wait_fn="$4"
  local count_fn="$5"

  local ready
  ready="$("${count_fn}")"
  if [[ "${ready}" -le "${target}" ]]; then
    return 0
  fi

  echo "Scaling Karpenter ${instance_type} pool down: ${ready} → ${target}..."
  read_aws_zones_array
  local num_zones="${#AWS_ZONES_ARRAY[@]}"
  local zone idx=0 replicas dep_name app_label="${deployment_prefix}"

  for zone in "${AWS_ZONES_ARRAY[@]}"; do
    [[ -z "${zone}" ]] && continue
    replicas="$(nodes_for_zone "${target}" "${idx}" "${num_zones}")"
    dep_name="$(karpenter_bootstrap_deployment_name "${deployment_prefix}" "${zone}")"
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${dep_name}
  namespace: kube-system
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: ${app_label}
      workshop.aerospike.com/zone: $(zone_resource_suffix "${zone}")
  template:
    metadata:
      labels:
        app: ${app_label}
        workshop.aerospike.com/zone: $(zone_resource_suffix "${zone}")
    spec:
      nodeSelector:
        node.kubernetes.io/instance-type: ${instance_type}
      tolerations:
        - operator: Exists
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: topology.kubernetes.io/zone
                    operator: In
                    values:
                      - ${zone}
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: ${app_label}
                  workshop.aerospike.com/zone: $(zone_resource_suffix "${zone}")
              topologyKey: kubernetes.io/hostname
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
EOF
    idx=$((idx + 1))
  done

  "${wait_fn}" "${target}"
  drain_excess_nodes_by_instance_type "${instance_type}" "${target}"
  delete_karpenter_bootstrap_deployments "${deployment_prefix}"
}

apply_karpenter_baseline_pool() {
  local total_count="${1:-${NODE_COUNT}}"
  apply_karpenter_ec2nodeclass
  apply_karpenter_pools_per_zone false
  bootstrap_karpenter_pool_per_zone "${NODE_TYPE}" "${total_count}" \
    "karpenter-bootstrap" wait_2xl_nodes
}

ensure_karpenter_baseline_pool() {
  local count="${1:-${NODE_COUNT}}"
  apply_karpenter_ec2nodeclass
  apply_karpenter_pools_per_zone false
  local ready
  ready="$(count_2xl_nodes_ready)"
  if [[ "${ready}" -gt "${count}" ]]; then
    scale_karpenter_pool_to_count "${NODE_TYPE}" "${count}" "karpenter-bootstrap" wait_2xl_nodes count_2xl_nodes_ready
  elif [[ "${ready}" -lt "${count}" ]]; then
    bootstrap_karpenter_pool_per_zone "${NODE_TYPE}" "${count}" \
      "karpenter-bootstrap" wait_2xl_nodes
  else
    echo "OK  Karpenter baseline NodePools active with ${ready} Ready nodes"
  fi
}

apply_karpenter_vertical_pool() {
  local total_count="${1:-${NODE_COUNT}}"
  apply_karpenter_pools_per_zone true
  bootstrap_karpenter_pool_per_zone "${NODE_TYPE_VERTICAL}" "${total_count}" \
    "karpenter-vertical-bootstrap" wait_4xl_nodes
}

wait_nvme_bootstrap() {
  wait_nvme_bootstrap_ready "$1" "${NVME_WAIT_TIMEOUT}"
}

maybe_wait_nvme_bootstrap() {
  local nodes_before="$1"
  local expected="$2"
  if ! kubectl -n kube-system get ds nvme-bootstrap >/dev/null 2>&1; then
    return 0
  fi
  local nodes_after ready desired waited=false
  nodes_after="$(count_2xl_nodes_ready)"
  ready="$(nvme_bootstrap_ready)"
  desired="$(nvme_bootstrap_desired)"
  if [[ "${nodes_after}" -gt "${nodes_before}" ]] || [[ "${ready:-0}" -lt "${desired:-0}" ]] || [[ "${ready:-0}" -lt "${expected}" ]]; then
    wait_nvme_bootstrap "${expected}"
    waited=true
  else
    echo "OK  nvme-bootstrap already Ready (${ready}/${desired})"
  fi
  if [[ "${waited}" == true ]]; then
    restart_local_volume_provisioner
  fi
}

ensure_2xl_pool() {
  local count="${NODE_COUNT}"
  local nodes_before
  nodes_before="$(count_2xl_nodes_ready)"
  echo "=== Ensuring 2xl workload pool (${NODE_TYPE} × ${count}, per-AZ) ==="

  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    ensure_karpenter_baseline_pool "${count}"
  else
    ensure_eksctl_pools_per_zone "${NODEGROUP_NAME}" "${NODE_TYPE}" "${count}" "baseline"
  fi

  print_zone_distribution "${NODE_TYPE}"
  if ! assert_multi_az_nodes fail "${NODE_TYPE}"; then
    echo "ERROR: multi-AZ distribution failed — run ./scripts/reset-cluster.sh --yes then prepare-lab.sh" >&2
    exit 1
  fi

  maybe_wait_nvme_bootstrap "${nodes_before}" "${count}"
  if [[ "${LAB_ID}" == "1.3" ]]; then
    ensure_local_ssd_pvs_for_pool "${NODE_TYPE}" "$(count_2xl_nodes_ready)" "baseline (${NODE_TYPE})"
  fi
}

scale_up_2xl() {
  local target=5
  local nodes_before
  nodes_before="$(count_2xl_nodes_ready)"
  echo "=== Scaling baseline pool to ${target} nodes (per-AZ) ==="
  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    apply_karpenter_baseline_pool "${target}"
  else
    ensure_eksctl_pools_per_zone "${NODEGROUP_NAME}" "${NODE_TYPE}" "${target}" "baseline"
  fi
  maybe_wait_nvme_bootstrap "${nodes_before}" "${target}"
}

ensure_vertical_4xl() {
  local nodes_before
  nodes_before="$(count_4xl_nodes_ready)"
  echo "=== Vertical scale: add ${NODE_TYPE_VERTICAL} pool per AZ (keep ${NODE_TYPE} pool) ==="

  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    apply_karpenter_vertical_pool "${NODE_COUNT}"
  else
    ensure_eksctl_pools_per_zone "${NODEGROUP_NAME_VERTICAL}" "${NODE_TYPE_VERTICAL}" "${NODE_COUNT}" "vertical"
  fi

  print_zone_distribution "${NODE_TYPE_VERTICAL}"
  validate_4xl_pool
  maybe_wait_nvme_bootstrap "${nodes_before}" "${NODE_COUNT}"
  if [[ "${LAB_ID}" == "1.3" ]]; then
    ensure_local_ssd_pvs_for_pool "${NODE_TYPE_VERTICAL}" "${NODE_COUNT}" "vertical (${NODE_TYPE_VERTICAL})"
  fi
}

validate_2xl_pool() {
  local expected="${1:-${NODE_COUNT}}"
  local exact="${2:-false}"
  echo "=== Validating baseline pool (expect ${expected}× ${NODE_TYPE} Ready, multi-AZ) ==="
  local ready
  ready="$(count_2xl_nodes_ready)"
  if [[ "${ready}" -lt "${expected}" ]]; then
    echo "FAIL only ${ready}× ${NODE_TYPE} nodes Ready (need ${expected})" >&2
    kubectl get nodes -o wide
    exit 1
  fi
  if [[ "${exact}" == true && "${ready}" -gt "${expected}" ]]; then
    echo "FAIL ${ready}× ${NODE_TYPE} nodes Ready (expected ${expected}) — run prepare-lab.sh to scale down" >&2
    kubectl get nodes -o wide
    exit 1
  fi
  print_zone_distribution "${NODE_TYPE}"
  if [[ "${expected}" -ge "${MIN_NODES_PER_ZONE}" ]] && ! assert_multi_az_nodes fail "${NODE_TYPE}"; then
    echo "Hint: run ./scripts/reset-cluster.sh --yes && ./scripts/labs/prepare-lab.sh ${LAB_ID}" >&2
    exit 1
  fi
  echo "OK  ${ready}× ${NODE_TYPE} Ready"
}

validate_4xl_pool() {
  echo "=== Validating 4xl pool (expect ${NODE_COUNT}× ${NODE_TYPE_VERTICAL} Ready, multi-AZ) ==="
  local ready
  ready="$(count_4xl_nodes_ready)"
  if [[ "${ready}" -lt "${NODE_COUNT}" ]]; then
    echo "FAIL only ${ready}× ${NODE_TYPE_VERTICAL} nodes Ready (need ${NODE_COUNT})" >&2
    kubectl get nodes -o wide
    exit 1
  fi
  print_zone_distribution "${NODE_TYPE_VERTICAL}"
  if ! assert_multi_az_nodes fail "${NODE_TYPE_VERTICAL}"; then
    exit 1
  fi
  echo "OK  ${ready}× ${NODE_TYPE_VERTICAL} Ready"
}

validate_min_nodes() {
  local min="$1"
  echo "=== Validating ≥${min} workload nodes ==="
  local ready
  ready="$(count_workload_nodes_ready)"
  if [[ "${ready}" -lt "${min}" ]]; then
    echo "FAIL only ${ready} workload nodes Ready (need ${min})" >&2
    exit 1
  fi
  echo "OK  ${ready} workload nodes Ready"
}

case "${LAB_ID}:${ACTION}" in
  1.1:ensure)
    if [[ "${VERTICAL}" == true ]]; then
      echo "ERROR: --vertical is for labs 1.3 and 1.4 only" >&2
      exit 1
    fi
    if [[ "${SCALE_UP}" == true ]]; then
      ensure_2xl_pool
      scale_up_2xl
    else
      ensure_2xl_pool
    fi
    ;;
  1.1:validate)
    if [[ "${SCALE_UP}" == true ]]; then
      validate_2xl_pool 5
    else
      validate_2xl_pool "${NODE_COUNT}"
    fi
    ;;
  1.2:ensure)
    ensure_2xl_pool
    ;;
  1.2:validate)
    validate_2xl_pool "${NODE_COUNT}" true
    ;;
  1.3:ensure)
    if [[ "${VERTICAL}" == true ]]; then
      ensure_vertical_4xl
    else
      ensure_2xl_pool
    fi
    ;;
  1.3:validate)
    if [[ "${VERTICAL}" == true ]]; then
      validate_4xl_pool
      validate_lab_1_3_vertical_local_storage
    else
      validate_2xl_pool "${NODE_COUNT}" true
      validate_lab_1_3_baseline_local_storage
    fi
    ;;
  1.4:ensure)
    if [[ "${VERTICAL}" == true ]]; then
      ensure_vertical_4xl
    else
      ensure_2xl_pool
    fi
    ;;
  1.4:validate)
    if [[ "${VERTICAL}" == true ]]; then
      validate_4xl_pool
    else
      validate_2xl_pool "${NODE_COUNT}" true
    fi
    ;;
  1.5:ensure)
    ensure_2xl_pool
    ;;
  1.5:validate)
    validate_min_nodes 3
    ;;
  *)
    echo "ERROR: unsupported lab/action: ${LAB_ID} ${ACTION}" >&2
    exit 1
    ;;
esac

echo "lab-nodes.sh ${LAB_ID} ${ACTION} complete."
