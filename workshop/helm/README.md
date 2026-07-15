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

Pin chart version to match AKO version (e.g. `--version=4.2.0`).

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

Each lab manifest under `manifests/` has a paired file under `helm/` with equivalent values.
