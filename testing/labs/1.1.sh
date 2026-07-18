#!/usr/bin/env bash
# testing/labs/1.1.sh — Lab 1.1: Horizontal Scaling
#
# Non-optional path: prepare -> deploy baseline (3) -> load data -> scale up
# to 5 -> scale back down to 3, asserting CR phase + pod counts at each step.
set -euo pipefail
LAB_ID="1.1"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"

"${LABS}/prepare-lab.sh" 1.1

apply_cluster_change dim-cluster
wait_pods_running "aerospike.com/cr=aerocluster" 3 600
wait_cr_phase Completed 600

"${LABS}/load-data.sh"
log_info "Baseline cluster size evidence:"
run_asadm "show stat like cluster_size"

"${LABS}/lab-nodes.sh" 1.1 ensure --scale-up
"${LABS}/lab-nodes.sh" 1.1 validate --scale-up

log_info "Scaling 3 -> 5 nodes..."
apply_cluster_change dim-cluster-scale-5
wait_pods_running "aerospike.com/cr=aerocluster" 5 900
wait_cr_phase Completed 900
log_info "Post-scale-up migrate stats (evidence):"
run_asadm "show stat like migrate"

log_info "Scaling 5 -> 3 nodes (back to baseline)..."
apply_cluster_change dim-cluster
wait_pods_running "aerospike.com/cr=aerocluster" 3 900
wait_cr_phase Completed 900

"${LABS}/lab-nodes.sh" 1.1 validate

running="$(kubectl -n "${NAMESPACE}" get pods -l aerospike.com/cr=aerocluster --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "${running}" "3" "final pod count" || fail_lab "Lab 1.1 final pod count mismatch"
assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 1.1 final CR phase mismatch"

echo "=== Lab 1.1: PASS ==="
