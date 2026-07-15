# Post-Setup Checklist

Run after Section 0 (environment built).

## Cluster

```bash
kubectl get nodes
```

- [ ] Expected node count Ready (4 for main cluster)

## Operator

Path A:

```bash
kubectl get csv -n operators | grep aerospike
```

- [ ] CSV phase `Succeeded`

Path B:

```bash
helm list -n operators
```

- [ ] Release `deployed`

## Platform

```bash
kubectl get storageclass ssd
kubectl -n aerospike get secrets
kubectl -n aerospike get aerospikecluster
```

- [ ] StorageClass `ssd` exists
- [ ] Secrets present
- [ ] No AerospikeCluster yet (Section 0 end state)

## Full validation

```bash
cd workshop && ./scripts/setup/08-validate-environment.sh
```

- [ ] Exit code 0
