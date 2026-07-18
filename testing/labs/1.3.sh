#!/usr/bin/env bash
# testing/labs/1.3.sh — Lab 1.3: Rack Replacement
#
# Non-optional path: deploy rack v1 baseline (racks 1+2) -> add vertical pool
# -> rack replacement (racks 3+4 replace 1+2) -> replace the guide's
# interactive `watch info` with a scripted settle-wait -> assert only racks
# 3+4 remain, on vertical/i8g.4xlarge, CR Completed.
set -euo pipefail
LAB_ID="1.3"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"

"${LABS}/prepare-lab.sh" 1.3

if [[ "${DEPLOY_PATH}" == "helm" ]]; then
  "${LABS}/deploy-rack-cluster-helm.sh"
else
  "${LABS}/deploy-rack-cluster.sh"
fi

wait_pods_running "aerospike.com/cr=aerocluster" 4 600
wait_cr_phase Completed 600
"${LABS}/lab-nodes.sh" 1.3 validate

v1_pod="$(first_pod_matching '\-v1\-')"
assert_not_empty "${v1_pod}" "baseline (v1) pod found"
assert_eq "$(pod_field "${v1_pod}" '{.spec.nodeSelector.workshop\.aerospike\.com/node-pool}')" "baseline" \
  "Phase 1 nodeSelector (${v1_pod})" || fail_lab "Lab 1.3 Phase 1 nodeSelector mismatch"

"${LABS}/lab-nodes.sh" 1.3 ensure --vertical
"${LABS}/lab-nodes.sh" 1.3 validate --vertical

if [[ "${DEPLOY_PATH}" == "helm" ]]; then
  "${LABS}/deploy-rack-cluster-replacement-helm.sh"
else
  "${LABS}/deploy-rack-cluster-replacement.sh"
fi

# Replaces the guide's interactive `asadm watch info` — poll until only racks
# 3+4 remain and CR is back to Completed (migration finished).
wait_rack_replacement_settled 4 '-(1|2)-v1-' 1200
log_info "Post-replacement migrate stats (evidence):"
run_asadm "show stat like migrate"

assert_no_pods_matching '\-1\-v1\-' "no rack 1 pods" || fail_lab "Lab 1.3: rack 1 pods still present"
assert_no_pods_matching '\-2\-v1\-' "no rack 2 pods" || fail_lab "Lab 1.3: rack 2 pods still present"

new_pod="$(first_pod_matching '\-3\-v1\-')"
assert_not_empty "${new_pod}" "rack 3 pod found"
assert_eq "$(pod_field "${new_pod}" '{.spec.nodeSelector.workshop\.aerospike\.com/node-pool}')" "vertical" \
  "Phase 3 nodeSelector (${new_pod})" || fail_lab "Lab 1.3 Phase 3 nodeSelector mismatch"
assert_eq "$(pod_field "${new_pod}" '{.spec.containers[?(@.name=="aerospike-server")].resources.limits.memory}')" "115Gi" \
  "Phase 3 memory limit (${new_pod})" || fail_lab "Lab 1.3 Phase 3 memory mismatch"

"${LABS}/lab-nodes.sh" 1.3 validate --vertical
assert_eq "$(cr_phase)" "Completed" "final CR phase" || fail_lab "Lab 1.3 final CR phase mismatch"

echo "=== Lab 1.3: PASS ==="
