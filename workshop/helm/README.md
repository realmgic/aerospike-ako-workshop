# Helm values ↔ AerospikeCluster CR field mapping

## Chart repository

```bash
helm repo add aerospike https://aerospike.github.io/aerospike-kubernetes-enterprise
helm repo update
```

## Releases

| Release | Chart | Namespace |
|---------|-------|-----------|
| `aerospike-kubernetes-operator` | `aerospike/aerospike-kubernetes-operator` | `operators` |
| `aerocluster` | `aerospike/aerospike-cluster` | `aerospike` |

Pin chart version to match the installed AKO operator. Lab scripts call `resolve_cluster_helm_chart_version()` (see `scripts/lib/common.sh`); for manual commands after Lab 2.2, use that helper instead of hardcoding `4.2.0`.

## Values ↔ CR mapping

| Helm values key | CR field |
|-----------------|----------|
| `replicas` | `spec.size` |
| `image.repository` / `image.tag` | `spec.image` |
| `rackConfig` | `spec.rackConfig` |
| `storage` | `spec.storage` |
| `podSpec` | `spec.podSpec` |
| `operations` | `spec.operations` |
| `k8sNodeBlockList` | `spec.k8sNodeBlockList` |
| `enableDynamicConfigUpdate` | `spec.enableDynamicConfigUpdate` |
| `batchSize` | `spec.batchSize` |

## Lab artifacts

Each lab AerospikeCluster manifest under `manifests/` has equivalent Helm values. Storage-specific config lives in the **base** files; lab deltas live in **overlay** files.

### Base + overlay layering

Full cluster specs live in two storage-specific base files:

- `helm/base-dim-cluster-values.yaml` — in-memory baseline (8.1.0.0)
- `helm/base-disk-cluster-values.yaml` — device baseline (8.1.0.0)

Lab-specific Helm files are **thin overlays** merged with `-f` (later files override earlier keys). Most overlays are **shared** (same file for disk and dim) because the delta is storage-agnostic; replication-factor and Section 3 TLS overlays differ by storage engine because they replace `storage.volumes`, which is not identical between the disk and dim base files (Helm merges lists by full replacement, not by append).

Example — warm restart on device storage:

```bash
helm upgrade --install aerocluster aerospike/aerospike-cluster \
  -f helm/base-disk-cluster-values.yaml \
  -f helm/overlay-pod-warm-restart-op-values.yaml \
  ...
```

In-memory: swap the base to `helm/base-dim-cluster-values.yaml`; the overlay file is the same.

Lab scripts call `build_cluster_helm_value_args()` in `scripts/lib/cluster-storage.sh` to resolve the correct base + overlay chain for `CLUSTER_STORAGE=disk|dim`.

**Naming rule:** `base-` prefix = full storage baseline; `overlay-` prefix = thin lab delta merged with `-f`. Within overlays, `overlay-dim-` / `overlay-disk-` means content differs by storage engine:

- `overlay-{dim,disk}-replication-factor-rf3-values.yaml`
- `overlay-{dim,disk}-cluster-tls-standard-values.yaml` (Lab 3.2)
- `overlay-{dim,disk}-cluster-tls-mtls-values.yaml` (Lab 3.3 Phase A/B)
- `overlay-{dim,disk}-cluster-tls-mtls-pki-only-values.yaml` (Lab 3.3 Phase C)
- `overlay-{dim,disk}-cluster-tls-mtls-blacklist-values.yaml` (Lab 3.5)

Standalone full specs (`rack-cluster-*`, `operator-values.yaml`) have no prefix.

**Exceptions (setup/demo only — no Helm pair):**

- `manifests/aerospike_local_volume_provisioner.yaml`
- `manifests/local-ssd-demo.yaml`

**Exceptions (no dim/disk variant — rack lab only):**

- `helm/rack-cluster-*.yaml`
- `helm/operator-values.yaml`
