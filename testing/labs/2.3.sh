#!/usr/bin/env bash
# testing/labs/2.3.sh — Lab 2.3: On-Demand Operations (Warm vs Cold Restart)
#
# Non-optional path: warm restart (no pod restart, startTime unchanged) then
# pod (cold) restart (startTime/restartCount change) — replaces the guide's
# Terminal-B live observation with snapshot/diff assertions.
set -euo pipefail
LAB_ID="2.3"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"

"${LABS}/prepare-lab.sh" 2.3

wait_pods_running "aerospike.com/cr=aerocluster" 3 600
wait_cr_phase Completed 600
assert_contains "$(cr_image)" "8.1.0" "baseline DB image before on-demand ops" || fail_lab "Lab 2.3: expected 8.1.0.x baseline image"

before1="$(snapshot_pods)"
apply_cluster_change pod-warm-restart-op
wait_cr_phase Completed 300
after1="$(snapshot_pods)"
assert_pods_unchanged "${before1}" "${after1}" "warm restart" || fail_lab "Lab 2.3: warm restart unexpectedly restarted pod containers"

before2="${after1}"
apply_cluster_change pod-restart-op
wait_cr_phase Completed 300
after2="$(snapshot_pods)"
assert_pods_changed "${before2}" "${after2}" "cold (pod) restart" || fail_lab "Lab 2.3: cold restart did not change pod identity/startTime/restartCount"

wait_pods_running "aerospike.com/cr=aerocluster" 3 300
assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 2.3 final CR phase mismatch"

echo "=== Lab 2.3: PASS ==="
