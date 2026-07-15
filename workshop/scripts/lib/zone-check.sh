#!/usr/bin/env bash
# Multi-AZ node distribution helpers for rack-aware labs.
set -euo pipefail

# Requires load_env() to have run (AWS_ZONES, MIN_NODES_PER_ZONE).

count_nodes_in_zone() {
  local zone="$1"
  local instance_type="${2:-}"
  local selector="topology.kubernetes.io/zone=${zone}"
  if [[ -n "${instance_type}" ]]; then
    selector="${selector},node.kubernetes.io/instance-type=${instance_type}"
  fi
  kubectl get nodes -l "${selector}" --no-headers 2>/dev/null \
    | grep -c ' Ready ' || true
}

# Print zone → Ready node counts (one line per zone in AWS_ZONES).
# Optional second arg: filter by instance type (e.g. i8g.4xlarge).
print_zone_distribution() {
  local instance_type="${1:-}"
  local zone
  IFS=',' read -ra zones <<< "${AWS_ZONES}"
  for zone in "${zones[@]}"; do
    zone="${zone// /}"
    [[ -z "${zone}" ]] && continue
    if [[ -n "${instance_type}" ]]; then
      echo "  ${zone}: $(count_nodes_in_zone "${zone}" "${instance_type}") Ready (${instance_type})"
    else
      echo "  ${zone}: $(count_nodes_in_zone "${zone}") Ready"
    fi
  done
}

# assert_multi_az_nodes [warn|fail] [instance_type]
# Returns 0 when every AWS_ZONES zone has >= MIN_NODES_PER_ZONE Ready nodes.
# Optional instance_type filters counts (required when 2xl and 4xl pools coexist).
assert_multi_az_nodes() {
  local mode="${1:-fail}"
  local instance_type="${2:-}"
  local zone
  local issues=()

  IFS=',' read -ra zones <<< "${AWS_ZONES}"
  for zone in "${zones[@]}"; do
    zone="${zone// /}"
    [[ -z "${zone}" ]] && continue
    local count
    count="$(count_nodes_in_zone "${zone}" "${instance_type}")"
    if [[ "${count}" -lt "${MIN_NODES_PER_ZONE}" ]]; then
      issues+=("${zone} has ${count} Ready node(s), need ${MIN_NODES_PER_ZONE}")
    fi
  done

  if [[ "${#issues[@]}" -eq 0 ]]; then
    return 0
  fi

  local prefix="FAIL"
  [[ "${mode}" == "warn" ]] && prefix="WARN"

  local filter_msg=""
  [[ -n "${instance_type}" ]] && filter_msg=" instance-type=${instance_type}"
  echo "${prefix} multi-AZ node distribution (MIN_NODES_PER_ZONE=${MIN_NODES_PER_ZONE}${filter_msg}):" >&2
  for msg in "${issues[@]}"; do
    echo "  ${msg}" >&2
  done
  print_zone_distribution "${instance_type}" >&2
  return 1
}
