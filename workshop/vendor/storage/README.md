# Vendored storage manifests

Copied from upstream for standalone workshop use (no sibling k8s monorepo required).

| File | Upstream source |
|------|-----------------|
| `eks_ssd_storage_class.yaml` | [aerospike-kubernetes-operator](https://github.com/aerospike/aerospike-kubernetes-operator) `config/samples/storage/eks_ssd_storage_class.yaml` |
| `local_storage_class.yaml` | Same repo, `config/samples/storage/local_storage_class.yaml` |
| `local_volume_provisioner_cleanup.yaml` | k8s repo local PVC cleanup controller |
| `local_volume_provisioner_cleanup_rbac.yaml` | k8s repo RBAC for cleanup controller |

Refresh when bumping AKO baseline or storage class definitions change.
