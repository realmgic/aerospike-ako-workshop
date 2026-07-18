#!/usr/bin/env bash
# testing/labs/2.1.sh — Lab 2.1: akoctl Install and Log Collection
set -euo pipefail
LAB_ID="2.1"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"

"${LABS}/prepare-lab.sh" 2.1

"${WORKSHOP_SCRIPTS}/setup/04-install-akoctl.sh"
krew_list="$(kubectl krew list 2>/dev/null || true)"
assert_contains "${krew_list}" "akoctl" "krew list contains akoctl" || fail_lab "Lab 2.1: akoctl not installed via krew"

ARTIFACT_DIR="${TEST_RUN_ARTIFACTS_DIR:-/tmp}/akoctl-2.1-$$"
"${LABS}/akoctl-collectinfo.sh" "${ARTIFACT_DIR}"
tarball_count="$(find "${ARTIFACT_DIR}" -type f \( -name '*.tar.gzip' -o -name '*.tar.gz' \) 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${tarball_count}" -ge 1 ]]; then
  log_pass "collectinfo produced ${tarball_count} tarball(s) under ${ARTIFACT_DIR}"
else
  fail_lab "Lab 2.1: no collectinfo tarball found under ${ARTIFACT_DIR}"
fi

wait_pods_running "aerospike.com/cr=aerocluster" 3 300
assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 2.1 final CR phase mismatch"

echo "=== Lab 2.1: PASS ==="
