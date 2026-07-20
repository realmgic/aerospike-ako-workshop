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

Each lab AerospikeCluster manifest under `manifests/` has equivalent Helm values. Storage variants use explicit **`dim-`** (in-memory) or **`disk-`** (device) prefixes.

### Base + overlay layering

Full cluster specs live in two base files only:

- `helm/dim-cluster-values.yaml` — in-memory baseline (8.1.0.0)
- `helm/disk-cluster-values.yaml` — device baseline (8.1.0.0)

Lab-specific Helm files are **thin overlays** merged with `-f` (later files override earlier keys). Example — warm restart on device storage:

```bash
helm upgrade --install aerocluster aerospike/aerospike-cluster \
  -f helm/disk-cluster-values.yaml \
  -f helm/disk-pod-warm-restart-op-values.yaml \
  ...
```

Lab scripts call `build_cluster_helm_value_args()` in `scripts/lib/cluster-storage.sh` to resolve the correct base + overlay chain for `CLUSTER_STORAGE=disk|dim`.

**Exceptions (setup/demo only — no Helm pair):**

- `manifests/aerospike_local_volume_provisioner.yaml`
- `manifests/local-ssd-demo.yaml`

**Exceptions (no dim/disk variant — rack lab only):**

- `helm/rack-cluster-*.yaml`
- `helm/operator-values.yaml`
