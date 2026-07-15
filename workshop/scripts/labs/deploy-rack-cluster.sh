#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl

kubectl apply -f "${WORKSHOP_ROOT}/manifests/rack-cluster-v1.yaml"
echo "Rack v1 cluster applied."
