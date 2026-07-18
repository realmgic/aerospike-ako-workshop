#!/usr/bin/env bash
# Local NVMe provisioner + automated disk bootstrap (nvme-bootstrap DaemonSet)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/local-storage.sh"
load_env
ensure_target_kubecontext

require_cmd kubectl

SETUP_DIR="$(dirname "$0")"
VENDOR_STORAGE="$(vendor_storage_dir)"
MANIFESTS_DIR="${WORKSHOP_ROOT}/manifests"
DISK_LAYOUTS="${WORKSHOP_ROOT}/config/disk-layouts.yaml"
LAYOUT_RENDERED="$(mktemp)"

kubectl apply -f "${VENDOR_STORAGE}/local_storage_class.yaml"
kubectl apply -f "${MANIFESTS_DIR}/aerospike_local_volume_provisioner.yaml"

for f in local_volume_provisioner_cleanup_rbac.yaml local_volume_provisioner_cleanup.yaml; do
  if [[ ! -f "${VENDOR_STORAGE}/${f}" ]]; then
    echo "ERROR: required file missing: ${VENDOR_STORAGE}/${f}" >&2
    exit 1
  fi
  kubectl apply -f "${VENDOR_STORAGE}/${f}"
done

# Render disk layout ConfigMap (optional NVME_DISK_LAYOUT override)
: "${NVME_DISK_LAYOUT:=}"
if [[ ! -f "${DISK_LAYOUTS}" ]]; then
  echo "ERROR: disk layout file missing: ${DISK_LAYOUTS}" >&2
  exit 1
fi
sed "s/^force_layout:.*$/force_layout: \"${NVME_DISK_LAYOUT}\"/" "${DISK_LAYOUTS}" > "${LAYOUT_RENDERED}"

kubectl create configmap nvme-disk-layouts \
  --from-file=disk-layouts.yaml="${LAYOUT_RENDERED}" \
  --from-file=nvme-init.py="${SETUP_DIR}/nvme-init.py" \
  -n kube-system \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "${LAYOUT_RENDERED}"

echo "Applying NVMe bootstrap DaemonSet..."
kubectl apply -f "${SETUP_DIR}/nvme-bootstrap-daemonset.yaml"

ready="$(nvme_bootstrap_ready)"
desired="$(nvme_bootstrap_desired)"
if [[ "${desired}" -gt 0 ]]; then
  wait_nvme_bootstrap_ready "${desired}"
  restart_local_volume_provisioner
  pv_count="$(count_local_ssd_pvs)"
  echo "local-ssd PVs discovered: ${pv_count}"
else
  echo "nvme-bootstrap not scheduled yet — run step 0.2-nodes first; PV restart runs in 0.6 validation."
fi

kubectl -n kube-system get ds nvme-bootstrap 2>/dev/null || true
echo "Local storage manifests applied (NODE_PROVISIONING=${NODE_PROVISIONING})."
