#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/render-yaml.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl

render_workshop_yaml "${WORKSHOP_ROOT}/manifests/rack-cluster-replacement.yaml" | kubectl apply -f -
echo "Rack replacement cluster applied."
