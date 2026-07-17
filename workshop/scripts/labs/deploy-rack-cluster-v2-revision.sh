#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/render-yaml.sh"
load_env
ensure_main_kubecontext
require_cmd kubectl

render_workshop_yaml "${WORKSHOP_ROOT}/manifests/rack-cluster-v2-revision.yaml" | kubectl apply -f -
echo "Rack v2 revision cluster applied."
