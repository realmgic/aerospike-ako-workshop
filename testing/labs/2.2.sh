#!/usr/bin/env bash
# testing/labs/2.2.sh — Lab 2.2: Upgrade AKO (Sequential Ladder)
#
# Runs the full ladder (4.2.0 -> 4.3.0 -> 4.4.1 -> 4.5.0) unattended via the
# existing upgrade-all-{olm,helm}.sh scripts, then verifies the final version
# and — filling a gap in the guide's own Verify section — asserts the
# Aerospike DB image stayed on 8.1.0.x throughout the AKO upgrade.
set -euo pipefail
LAB_ID="2.2"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"

if ! kubectl -n "${NAMESPACE}" get aerospikecluster aerocluster >/dev/null 2>&1; then
  fail_lab "Lab 2.2 requires Lab 2.1's cluster to already be deployed — run testing/run-lab.sh 2.1 first"
fi

wait_pods_running "aerospike.com/cr=aerocluster" 3 300
wait_cr_phase Completed 300

start_image="$(cr_image)"
assert_contains "${start_image}" "8.1.0" "starting DB image" || fail_lab "Lab 2.2: expected 8.1.0.x baseline image before upgrade"

UPGRADE_DIR="${LABS}/upgrade-ako"
if [[ "${DEPLOY_PATH}" == "helm" ]]; then
  "${UPGRADE_DIR}/upgrade-all-helm.sh"
else
  "${UPGRADE_DIR}/upgrade-all-olm.sh"
fi

"${UPGRADE_DIR}/verify-ako-version.sh" "${AKO_VERSION_TARGET}"

# Known gap: neither the guide nor verify-ako-version.sh asserts the DB image
# is unchanged by the AKO upgrade — added here.
end_image="$(cr_image)"
assert_contains "${end_image}" "8.1.0" "DB image unchanged after AKO upgrade" || \
  fail_lab "Lab 2.2: DB image changed during AKO upgrade (${start_image} -> ${end_image}), expected to stay 8.1.0.x"

wait_pods_running "aerospike.com/cr=aerocluster" 3 300
wait_cr_phase Completed 300

echo "=== Lab 2.2: PASS ==="
