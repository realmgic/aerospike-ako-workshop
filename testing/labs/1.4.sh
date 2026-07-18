#!/usr/bin/env bash
# testing/labs/1.4.sh — Lab 1.4: Dynamic Replication Factor
#
# Requires AKO >= 4.4.0 (run after Lab 2.2 in curriculum order). Non-optional
# path: baseline RF=2 -> apply RF=3 (no rolling restart expected) -> assert
# RF=3 + pods unchanged -> revert to RF=2 -> assert again.
set -euo pipefail
LAB_ID="1.4"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"

"${LABS}/prepare-lab.sh" 1.4

apply_cluster_change dim-cluster
wait_pods_running "aerospike.com/cr=aerocluster" 3 600
wait_cr_phase Completed 600
"${LABS}/lab-nodes.sh" 1.4 validate

assert_eq "$(cr_replication_factor)" "2" "baseline replication-factor" || fail_lab "Lab 1.4 baseline RF mismatch"
log_info "Baseline replication-factor evidence:"
run_asadm "show config like replication-factor"

before1="$(snapshot_pods)"
apply_cluster_change replication-factor-rf3
wait_cr_phase Completed 300
after1="$(snapshot_pods)"
assert_pods_unchanged "${before1}" "${after1}" "RF 2->3" || fail_lab "Lab 1.4: unexpected rolling restart on RF change to 3"
assert_eq "$(cr_replication_factor)" "3" "RF=3 after apply" || fail_lab "Lab 1.4: RF did not become 3"

before2="${after1}"
apply_cluster_change dim-cluster
wait_cr_phase Completed 300
after2="$(snapshot_pods)"
assert_pods_unchanged "${before2}" "${after2}" "RF 3->2 (revert)" || fail_lab "Lab 1.4: unexpected rolling restart on RF revert to 2"
assert_eq "$(cr_replication_factor)" "2" "RF=2 after revert" || fail_lab "Lab 1.4: RF did not revert to 2"

log_info "Final replication-factor evidence:"
run_asadm "show config like replication-factor"
assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 1.4 final CR phase mismatch"

echo "=== Lab 1.4: PASS ==="
