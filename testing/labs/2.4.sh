#!/usr/bin/env bash
# testing/labs/2.4.sh — Lab 2.4: Upgrade Aerospike Database
#
# Known gap fill: the guide's Path B (Helm) only says "update the values file
# and upgrade" without giving the exact command — apply_cluster_change here
# runs the equivalent `helm upgrade -f helm/disk-aerospike-upgrade-values.yaml`
# directly (that values file already pins 8.1.2.0).
set -euo pipefail
LAB_ID="2.4"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lab-env.sh"

"${LABS}/prepare-lab.sh" 2.4

wait_pods_running "aerospike.com/cr=aerocluster" 3 600
wait_cr_phase Completed 600
assert_contains "$(cr_image)" "8.1.0" "baseline DB image before upgrade" || fail_lab "Lab 2.4: expected 8.1.0.x baseline image"
log_info "Baseline replication-factor evidence:"
run_asadm "show config like replication-factor"

apply_cluster_change aerospike-upgrade

wait_pods_running "aerospike.com/cr=aerocluster" 3 900
wait_cr_phase Completed 900

assert_contains "$(cr_image)" "8.1.2" "DB image after upgrade" || fail_lab "Lab 2.4: DB image did not reach 8.1.2.x"

echo "=== Lab 2.4: PASS ==="
