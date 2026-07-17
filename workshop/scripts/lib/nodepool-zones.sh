#!/usr/bin/env bash
# Per-AZ workload pool naming and node count helpers.
# Requires load_env() (AWS_ZONES, NODEGROUP_NAME, KARPENTER_NODEPOOL_NAME, etc.).
set -euo pipefail

AWS_ZONES_ARRAY=()

read_aws_zones_array() {
  AWS_ZONES_ARRAY=()
  local zone
  IFS=',' read -ra AWS_ZONES_ARRAY <<< "${AWS_ZONES}"
  for i in "${!AWS_ZONES_ARRAY[@]}"; do
    zone="${AWS_ZONES_ARRAY[$i]// /}"
    AWS_ZONES_ARRAY[$i]="${zone}"
  done
}

pool_name_for_zone() {
  local base="$1"
  local zone="$2"
  echo "${base}-${zone}"
}

# DNS-safe suffix for bootstrap Deployment names (zones contain no invalid chars today).
zone_resource_suffix() {
  echo "${1//./-}"
}

# Split total node count across zones; remainder goes to first zones (5 → 3+2).
nodes_for_zone() {
  local total="$1"
  local zone_index="$2"
  local num_zones="$3"
  local per_zone=$((total / num_zones))
  local remainder=$((total % num_zones))
  if [[ "${zone_index}" -lt "${remainder}" ]]; then
    echo $((per_zone + 1))
  else
    echo "${per_zone}"
  fi
}

baseline_pool_base_name() {
  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    echo "${KARPENTER_NODEPOOL_NAME}"
  else
    echo "${NODEGROUP_NAME}"
  fi
}

vertical_pool_base_name() {
  if [[ "${NODE_PROVISIONING}" == "karpenter" ]]; then
    echo "${KARPENTER_NODEPOOL_VERTICAL_NAME}"
  else
    echo "${NODEGROUP_NAME_VERTICAL}"
  fi
}

list_baseline_pool_names() {
  read_aws_zones_array
  local base zone
  base="$(baseline_pool_base_name)"
  for zone in "${AWS_ZONES_ARRAY[@]}"; do
    [[ -z "${zone}" ]] && continue
    pool_name_for_zone "${base}" "${zone}"
  done
}

list_vertical_pool_names() {
  read_aws_zones_array
  local base zone
  base="$(vertical_pool_base_name)"
  for zone in "${AWS_ZONES_ARRAY[@]}"; do
    [[ -z "${zone}" ]] && continue
    pool_name_for_zone "${base}" "${zone}"
  done
}
