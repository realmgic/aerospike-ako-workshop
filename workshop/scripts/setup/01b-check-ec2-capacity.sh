#!/usr/bin/env bash
# Pre-flight EC2 AZ capacity for workshop workload instance types (Lab 0.1).
# Checks i8g.2xlarge (baseline) and i8g.4xlarge (Lab 1.2 vertical) in each AWS_ZONES entry.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/nodepool-zones.sh"
load_env

require_cmd aws

fail=0
PEAK_GVT_NODES=$((NODE_COUNT * 2))

arm64_ami() {
  aws ssm get-parameters \
    --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
    --region "${AWS_REGION}" \
    --query 'Parameters[0].Value' \
    --output text 2>/dev/null || true
}

subnet_in_zone() {
  local zone="$1"
  aws ec2 describe-subnets \
    --filters "Name=availability-zone,Values=${zone}" \
    --region "${AWS_REGION}" \
    --query 'Subnets[0].SubnetId' \
    --output text
}

check_instance_offered() {
  local zone="$1"
  local itype="$2"
  local count
  count="$(aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters "Name=instance-type,Values=${itype}" "Name=location,Values=${zone}" \
    --region "${AWS_REGION}" \
    --query 'length(InstanceTypeOfferings)' \
    --output text 2>/dev/null || echo 0)"
  if [[ "${count}" -ge 1 ]]; then
    echo "OK  ${zone} ${itype} offered in AZ"
    return 0
  fi
  echo "FAIL ${zone} ${itype} not offered in AZ"
  fail=1
  return 1
}

check_dry_run_capacity() {
  local zone="$1"
  local itype="$2"
  local ami="$3"
  local subnet ok i out

  subnet="$(subnet_in_zone "${zone}")"
  if [[ -z "${subnet}" || "${subnet}" == "None" ]]; then
    echo "FAIL ${zone} ${itype} — no subnet found (check AWS credentials / region ${AWS_REGION})"
    fail=1
    return 1
  fi

  ok=0
  for i in $(seq 1 "${MIN_NODES_PER_ZONE}"); do
    out="$(aws ec2 run-instances --dry-run \
      --instance-type "${itype}" \
      --image-id "${ami}" \
      --subnet-id "${subnet}" \
      --region "${AWS_REGION}" 2>&1 || true)"
    if grep -q DryRunOperation <<< "${out}"; then
      ok=$((ok + 1))
    elif grep -qi InsufficientInstanceCapacity <<< "${out}"; then
      :
    else
      echo "WARN ${zone} ${itype} dry-run ${i}/${MIN_NODES_PER_ZONE}: ${out}"
    fi
  done

  if [[ "${ok}" -eq "${MIN_NODES_PER_ZONE}" ]]; then
    echo "OK  ${zone} ${itype}: ${ok}/${MIN_NODES_PER_ZONE} on-demand dry-runs"
    return 0
  fi
  echo "FAIL ${zone} ${itype}: ${ok}/${MIN_NODES_PER_ZONE} on-demand dry-runs — InsufficientInstanceCapacity likely"
  fail=1
  return 1
}

check_gvt_quota() {
  local quota_value
  quota_value="$(aws service-quotas list-service-quotas \
    --service-code ec2 \
    --region "${AWS_REGION}" \
    --query 'Quotas[].[QuotaName,Value]' \
    --output text 2>/dev/null \
    | awk -F'\t' '/Running On-Demand G and VT/ { print $2; exit }' || true)"

  if [[ -z "${quota_value}" || "${quota_value}" == "None" ]]; then
    echo "SKIP G/VT on-demand quota (could not read Service Quotas — verify manually)"
    return 0
  fi

  if awk -v q="${quota_value}" -v need="${PEAK_GVT_NODES}" 'BEGIN { exit !(q + 0 >= need + 0) }'; then
    echo "OK  G/VT on-demand quota ${quota_value} (need >= ${PEAK_GVT_NODES} at Lab 1.2 peak)"
    return 0
  fi
  echo "FAIL G/VT on-demand quota ${quota_value} < ${PEAK_GVT_NODES} (Lab 1.2 peak: ${NODE_COUNT}× ${NODE_TYPE} + ${NODE_COUNT}× ${NODE_TYPE_VERTICAL})"
  fail=1
  return 1
}

echo "=== EC2 capacity pre-flight (${AWS_REGION}, zones: ${AWS_ZONES}) ==="
echo "Baseline: ${MIN_NODES_PER_ZONE}× ${NODE_TYPE} per zone (Lab 0.2)"
echo "Vertical: ${MIN_NODES_PER_ZONE}× ${NODE_TYPE_VERTICAL} per zone (Lab 1.2 Phase 2)"
echo ""

AMI="$(arm64_ami)"
if [[ -z "${AMI}" || "${AMI}" == "None" ]]; then
  echo "FAIL could not resolve ARM64 AL2023 AMI in ${AWS_REGION}"
  exit 1
fi

read_aws_zones_array
zone=""
for zone in "${AWS_ZONES_ARRAY[@]}"; do
  [[ -z "${zone}" ]] && continue
  check_instance_offered "${zone}" "${NODE_TYPE}"
  check_instance_offered "${zone}" "${NODE_TYPE_VERTICAL}"
  check_dry_run_capacity "${zone}" "${NODE_TYPE}" "${AMI}"
  check_dry_run_capacity "${zone}" "${NODE_TYPE_VERTICAL}" "${AMI}"
done

check_gvt_quota

if [[ "${fail}" -eq 0 ]]; then
  echo ""
  echo "EC2 capacity pre-flight passed."
  exit 0
fi

echo ""
echo "EC2 capacity pre-flight failed."
echo "Hint: try alternate AWS_ZONES in workshop.env before ./scripts/setup/02-bootstrap-eks.sh"
echo "      (both ${NODE_TYPE} and ${NODE_TYPE_VERTICAL} must pass in every zone)."
exit 1
