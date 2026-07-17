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

count_2xl_nodes_ready() {
  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    kubectl get nodes -l "workshop.aerospike.com/workload=aerospike,node.kubernetes.io/instance-type=${NODE_TYPE}" \
      --no-headers 2>/dev/null | grep -c ' Ready ' || true
  else
    kubectl get nodes -l "alpha.eksctl.io/nodegroup-name=${NODEGROUP_NAME}" --no-headers 2>/dev/null \
      | grep -c ' Ready ' || true
  fi
}

count_4xl_nodes_ready() {
  count_nodes_instance_type "${NODE_TYPE_VERTICAL}"
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

wait_nodes_instance_type() {
  local instance_type="$1"
  local expected="$2"
  local deadline=$((SECONDS + NODE_WAIT_TIMEOUT))
  while true; do
    local ready
    ready="$(count_nodes_instance_type "${instance_type}")"
    echo "  ${instance_type} nodes Ready: ${ready}/${expected}"
    if [[ "${ready}" -ge "${expected}" ]]; then
      return 0
    fi
    if [[ "${SECONDS}" -gt "${deadline}" ]]; then
      echo "ERROR: timed out waiting for ${expected}× ${instance_type} nodes" >&2
      kubectl get nodes -o wide
      exit 1
    fi
    sleep 15
  done
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

drain_excess_nodes_by_instance_type() {
  local instance_type="$1"
  local target="$2"
  local ready
  ready="$(count_nodes_instance_type "${instance_type}")"
  while [[ "${ready}" -gt "${target}" ]]; do
    local excess=$((ready - target))
    echo "Draining ${excess} excess ${instance_type} node(s) (${ready} > ${target})..."
    mapfile -t nodes < <(
      kubectl get nodes -l "node.kubernetes.io/instance-type=${instance_type}" \
        --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -n "${excess}"
    )
    for node in "${nodes[@]}"; do
      [[ -z "${node}" ]] && continue
      kubectl cordon "${node}"
      kubectl drain "${node}" --ignore-daemonsets --delete-emptydir-data --force --grace-period=120
    done
    ready="$(count_nodes_instance_type "${instance_type}")"
  done
}

scale_karpenter_pool_to_count() {
  local instance_type="$1"
  local target="$2"

  local ready
  ready="$(count_nodes_instance_type "${instance_type}")"
  if [[ "${ready}" -le "${target}" ]]; then
    return 0
  fi

  echo "Scaling Karpenter ${instance_type} pool down: ${ready} → ${target}..."
  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: karpenter-bootstrap-placeholder
  namespace: kube-system
spec:
  replicas: ${target}
  selector:
    matchLabels:
      app: karpenter-bootstrap-placeholder
  template:
    metadata:
      labels:
        app: karpenter-bootstrap-placeholder
    spec:
      nodeSelector:
        node.kubernetes.io/instance-type: ${instance_type}
      tolerations:
        - operator: Exists
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: karpenter-bootstrap-placeholder
              topologyKey: kubernetes.io/hostname
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
EOF

  wait_2xl_nodes "${target}"
  drain_excess_nodes_by_instance_type "${instance_type}" "${target}"
  kubectl delete deployment karpenter-bootstrap-placeholder -n kube-system --ignore-not-found
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

wait_nvme_bootstrap() {
  wait_nvme_bootstrap_ready "$1" "${NVME_WAIT_TIMEOUT}"
}

maybe_wait_nvme_bootstrap() {
  local nodes_before="$1"
  local expected="$2"
  if ! kubectl -n kube-system get ds nvme-bootstrap >/dev/null 2>&1; then
    return 0
  fi
  local nodes_after ready desired
  nodes_after="$(count_2xl_nodes_ready)"
  ready="$(nvme_bootstrap_ready)"
  desired="$(nvme_bootstrap_desired)"
  if [[ "${nodes_after}" -gt "${nodes_before}" ]] || [[ "${ready:-0}" -lt "${desired:-0}" ]] || [[ "${ready:-0}" -lt "${expected}" ]]; then
    wait_nvme_bootstrap "${expected}"
  else
    echo "OK  nvme-bootstrap already Ready (${ready}/${desired})"
  fi
}

apply_karpenter_workload_pool() {
  local instance_type="${1:-${NODE_TYPE}}"
  local min_nodes="${2:-${KARPENTER_NODEPOOL_MIN}}"

  require_cmd envsubst
  export CLUSTER_NAME AWS_REGION KARPENTER_CONSOLIDATION
  export NODE_TYPE="${instance_type}"
  export KARPENTER_NODEPOOL_NAME KARPENTER_NODECLASS_NAME
  export KARPENTER_NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
  IFS=',' read -r NODE_ZONE_A NODE_ZONE_B _ <<< "${AWS_ZONES},,"
  export NODE_ZONE_A NODE_ZONE_B

  local consolidate_after="30m"
  if [[ "${KARPENTER_CONSOLIDATION}" == "Off" ]]; then
    export KARPENTER_CONSOLIDATION="WhenEmpty"
    consolidate_after="720h"
  fi

  echo "Applying Karpenter EC2NodeClass and NodePool (instance ${instance_type})..."
  envsubst < "${KARPENTER_DIR}/01-ec2nodeclass-i8g.yaml" | kubectl apply -f -
  envsubst < "${KARPENTER_DIR}/02-nodepool-aerospike.yaml" | kubectl apply -f -
  kubectl patch nodepool "${KARPENTER_NODEPOOL_NAME}" --type=merge \
    -p "{\"spec\":{\"disruption\":{\"consolidateAfter\":\"${consolidate_after}\"}}}" 2>/dev/null || true

  echo "Deploying placeholder to reach min ${min_nodes} nodes..."
  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: karpenter-bootstrap-placeholder
  namespace: kube-system
spec:
  replicas: ${min_nodes}
  selector:
    matchLabels:
      app: karpenter-bootstrap-placeholder
  template:
    metadata:
      labels:
        app: karpenter-bootstrap-placeholder
    spec:
      tolerations:
        - operator: Exists
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: karpenter-bootstrap-placeholder
              topologyKey: kubernetes.io/hostname
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
EOF

  wait_2xl_nodes "${min_nodes}"
  kubectl delete deployment karpenter-bootstrap-placeholder -n kube-system --ignore-not-found
}

ensure_eksctl_nodegroup() {
  local name="$1"
  local node_type="$2"
  local count="$3"
  local pool_label="${4:-}"

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
      --node-zones "${AWS_ZONES}"
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
    echo "Creating nodegroup ${name} (${node_type} × ${count})..."
    eksctl create nodegroup "${create_args[@]}"
  fi
  wait_eksctl_nodegroup_ready "${name}" "${count}"
  if [[ -n "${pool_label}" ]]; then
    label_eksctl_nodegroup_pool "${name}" "${pool_label}"
  fi
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

ensure_2xl_pool() {
  local count="${NODE_COUNT}"
  local nodes_before
  nodes_before="$(count_2xl_nodes_ready)"
  echo "=== Ensuring 2xl workload pool (${NODE_TYPE} × ${count}) ==="

  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    if ! kubectl get nodepool "${KARPENTER_NODEPOOL_NAME}" >/dev/null 2>&1; then
      apply_karpenter_workload_pool "${NODE_TYPE}" "${count}"
    else
      local current_type
      current_type="$(kubectl get nodepool "${KARPENTER_NODEPOOL_NAME}" -o jsonpath='{.spec.template.spec.requirements[?(@.key=="node.kubernetes.io/instance-type")].values[0]}' 2>/dev/null || echo "")"
      if [[ "${current_type}" != "${NODE_TYPE}" ]]; then
        echo "NodePool instance type is ${current_type:-unknown}, expected ${NODE_TYPE} — re-applying..."
        apply_karpenter_workload_pool "${NODE_TYPE}" "${count}"
      else
        local ready
        ready="$(count_2xl_nodes_ready)"
        if [[ "${ready}" -gt "${count}" ]]; then
          scale_karpenter_pool_to_count "${NODE_TYPE}" "${count}"
        elif [[ "${ready}" -lt "${count}" ]]; then
          apply_karpenter_workload_pool "${NODE_TYPE}" "${count}"
        else
          echo "OK  Karpenter NodePool ${KARPENTER_NODEPOOL_NAME} active with ${ready} Ready nodes"
        fi
      fi
    fi
  else
    ensure_eksctl_nodegroup "${NODEGROUP_NAME}" "${NODE_TYPE}" "${count}" "baseline"
  fi

  print_zone_distribution "${NODE_TYPE}"
  if ! assert_multi_az_nodes fail "${NODE_TYPE}"; then
    echo "ERROR: multi-AZ distribution failed — run ./scripts/reset-cluster.sh --yes then prepare-lab.sh" >&2
    exit 1
  fi

  maybe_wait_nvme_bootstrap "${nodes_before}" "${count}"
}

scale_up_2xl() {
  local target=5
  local nodes_before
  nodes_before="$(count_2xl_nodes_ready)"
  echo "=== Scaling 2xl pool to ${target} nodes ==="
  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    apply_karpenter_workload_pool "${NODE_TYPE}" "${target}"
  else
    ensure_eksctl_nodegroup "${NODEGROUP_NAME}" "${NODE_TYPE}" "${target}" "baseline"
  fi
  maybe_wait_nvme_bootstrap "${nodes_before}" "${target}"
}

ensure_vertical_4xl() {
  echo "=== Vertical scale: add ${NODE_TYPE_VERTICAL} pool (keep ${NODE_TYPE} pool) ==="

  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    apply_karpenter_vertical_pool "${NODE_COUNT}"
  else
    ensure_eksctl_nodegroup "${NODEGROUP_NAME_VERTICAL}" "${NODE_TYPE_VERTICAL}" "${NODE_COUNT}" "vertical"
  fi

  print_zone_distribution "${NODE_TYPE_VERTICAL}"
  validate_4xl_pool
}

apply_karpenter_vertical_pool() {
  local count="${1:-${NODE_COUNT}}"

  require_cmd envsubst
  export CLUSTER_NAME AWS_REGION KARPENTER_CONSOLIDATION
  export NODE_TYPE_VERTICAL KARPENTER_NODEPOOL_VERTICAL_NAME KARPENTER_NODECLASS_NAME
  export KARPENTER_NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
  IFS=',' read -r NODE_ZONE_A NODE_ZONE_B _ <<< "${AWS_ZONES},,"
  export NODE_ZONE_A NODE_ZONE_B

  local consolidate_after="30m"
  if [[ "${KARPENTER_CONSOLIDATION}" == "Off" ]]; then
    export KARPENTER_CONSOLIDATION="WhenEmpty"
    consolidate_after="720h"
  fi

  echo "Applying Karpenter vertical NodePool ${KARPENTER_NODEPOOL_VERTICAL_NAME} (${NODE_TYPE_VERTICAL})..."
  envsubst < "${KARPENTER_DIR}/02-nodepool-aerospike-vertical.yaml" | kubectl apply -f -
  kubectl patch nodepool "${KARPENTER_NODEPOOL_VERTICAL_NAME}" --type=merge \
    -p "{\"spec\":{\"disruption\":{\"consolidateAfter\":\"${consolidate_after}\"}}}" 2>/dev/null || true

  local ready
  ready="$(count_4xl_nodes_ready)"
  if [[ "${ready}" -lt "${count}" ]]; then
    echo "Deploying vertical bootstrap placeholder to reach ${count}× ${NODE_TYPE_VERTICAL}..."
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: karpenter-vertical-bootstrap-placeholder
  namespace: kube-system
spec:
  replicas: ${count}
  selector:
    matchLabels:
      app: karpenter-vertical-bootstrap-placeholder
  template:
    metadata:
      labels:
        app: karpenter-vertical-bootstrap-placeholder
    spec:
      nodeSelector:
        node.kubernetes.io/instance-type: ${NODE_TYPE_VERTICAL}
      tolerations:
        - operator: Exists
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: karpenter-vertical-bootstrap-placeholder
              topologyKey: kubernetes.io/hostname
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
EOF
    wait_nodes_instance_type "${NODE_TYPE_VERTICAL}" "${count}"
    kubectl delete deployment karpenter-vertical-bootstrap-placeholder -n kube-system --ignore-not-found
  fi
}

validate_2xl_pool() {
  local expected="${1:-${NODE_COUNT}}"
  local exact="${2:-false}"
  echo "=== Validating 2xl pool (expect ${expected}× ${NODE_TYPE} Ready, multi-AZ) ==="
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
    else
      validate_2xl_pool "${NODE_COUNT}" true
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
