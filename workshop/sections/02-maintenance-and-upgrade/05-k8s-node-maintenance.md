# Lab 2.5 — K8s Worker Node Maintenance

| Field | Value |
|-------|-------|
| Lab ID | `2.5` |
| Section | Maintenance & Upgrade |
| EKS cluster | `my-cluster` |
| AKO min version | `4.5.0` |
| Aerospike baseline | dim or rack cluster |
| Deploy path | both |
| Node provisioning | both (blocklist **eksctl only**) |
| Duration | ~25 min |
| Validation status | `draft` |
| Official docs | [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance) |

## Takeaway

AKO's safe pod eviction webhook blocks drain until the Aerospike cluster is stable — protecting data during worker node maintenance.

## Prerequisites

- Lab 2.4 complete (on-demand operations; implies AKO **4.5.0** and DB upgrade done)
- `safePodEviction.enable=true` on operator (Helm values or OLM config)
- Cluster Running; note pod→node mapping

## Phase 0 — Baseline

Capture pod placement before either maintenance technique:

```bash
kubectl -n aerospike get pods -o wide
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'
NODE=$(kubectl -n aerospike get pods -o wide --no-headers | awk 'NR==1{print $7}')
```

**Expected:** 3 pods `Running`; CR phase `Completed`; `NODE` is a worker hosting an Aerospike pod.

## Steps — Drain path (primary)

1. Attempt drain:

   ```bash
   kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
   ```

   **Expected:** Eviction blocked or delayed; annotation `aerospike.com/eviction-blocked` may appear.

2. Observe blocked eviction:

   ```bash
   kubectl get pod -n aerospike -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.aerospike\.com/eviction-blocked}{"\n"}{end}'
   ```

3. Wait for AKO to finish migration:

   ```bash
   kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=300s
   ```

4. Retry drain:

   ```bash
   kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
   ```

5. Observe pod rescheduling:

   ```bash
   kubectl -n aerospike get pods -o wide -w
   ```

   Ctrl+C once all Aerospike pods are off `$NODE`.

**Pass:** Drain succeeds without `--force`; no Aerospike pods remain on `$NODE`.

## Steps — Alternate: k8sNodeBlockList (eksctl path only)

> **Karpenter sessions:** skip this section. Use [05-k8s-node-maintenance-karpenter.md](05-k8s-node-maintenance-karpenter.md) instead. `k8sNodeBlockList` uses node hostname affinity incompatible with Karpenter ([AKO #305](https://github.com/aerospike/aerospike-kubernetes-operator/issues/305)).

AKO migrates pods off listed nodes via rolling restart — useful for planned local-storage maintenance when drain is not the right entry point.

### Path A — kubectl

1. Edit `manifests/node-blocklist.yaml` — set `k8sNodeBlockList` to `$NODE`.
2. Apply and watch pods reschedule:

   ```bash
   kubectl apply -f manifests/node-blocklist.yaml
   kubectl -n aerospike get pods -o wide -w
   ```

   Ctrl+C once pods have moved off `$NODE`.

3. Wait for migration to complete:

   ```bash
   kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=300s
   ```

### Path B — Helm

1. Edit `helm/node-blocklist-values.yaml` — set `k8sNodeBlockList` to `$NODE`.
2. Apply and watch pods reschedule:

   ```bash
   helm upgrade aerocluster aerospike/aerospike-cluster \
     -n aerospike -f helm/node-blocklist-values.yaml --version=4.5.0
   kubectl -n aerospike get pods -o wide -w
   ```

   Ctrl+C once pods have moved off `$NODE`.

3. Wait for migration to complete:

   ```bash
   kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=300s
   ```

### Observe (blocklist)

```bash
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.spec.k8sNodeBlockList}{"\n"}'
kubectl -n aerospike get pods -o wide
```

**Expected:** Blocklist contains `$NODE`; no Aerospike pods scheduled on that node.

## Verify (pass/fail)

```bash
kubectl -n aerospike get pods -o wide
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'
```

**Pass:** All Aerospike pods `Running` on nodes other than the maintenance target; CR `Completed`.

## Observe

- Safe eviction webhook blocks API eviction until migration completes
- Blocklist triggers AKO-driven rolling migration (hostname affinity — eksctl only)
- Pods move in batches; cluster stays available during migration

## Teardown / restore

After the maintenance demo, restore `$NODE` and cluster scheduling so later labs can run normally.

### Restore the drained node (choose one)

Both options assume drain completed successfully (`$NODE` is cordoned and has no Aerospike pods). Choose **Option A** to simulate completed maintenance; choose **Option B** for a quick undo when replacement was not demonstrated. If only the blocklist path was used, cordon the target node first or skip to Option B if the node is already schedulable.

**Option A — Replace node after maintenance (eksctl)**

Simulates completing real node maintenance (patching / hardware) — terminate the drained instance and let the MNG roll in a replacement:

```bash
INSTANCE_ID=$(kubectl get node "$NODE" -o jsonpath='{.spec.providerID}' | sed 's|.*/||')
kubectl delete node "$NODE"
aws ec2 terminate-instances --region "${AWS_REGION}" --instance-ids "$INSTANCE_ID"
kubectl get nodes -w
```

Ctrl+C once a replacement node is `Ready`. `nvme-bootstrap` initializes NVMe on the new instance (Lab 0.5).

> **Karpenter sessions:** use [05-k8s-node-maintenance-karpenter.md](05-k8s-node-maintenance-karpenter.md) for NodeClaim replacement instead of Option A.

**Option B — Reset node back into the cluster (quick)**

Returns the same instance to the scheduling pool:

```bash
kubectl uncordon "$NODE"
kubectl get node "$NODE"
kubectl -n aerospike get pods -o wide
```

**Expected:** Node `Ready`, `SchedulingEnabled`. Aerospike pods remain on other nodes.

### Clear blocklist (if blocklist path was used)

Skip if only the drain path was demonstrated. Do not re-apply `manifests/dim-cluster.yaml` — `manifests/node-blocklist.yaml` uses a different resource profile.

**Path A — kubectl:**

```bash
kubectl -n aerospike patch aerospikecluster aerocluster --type=json \
  -p='[{"op": "remove", "path": "/spec/k8sNodeBlockList"}]'
kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=300s
```

**Path B — Helm:**

```bash
helm upgrade aerocluster aerospike/aerospike-cluster \
  -n aerospike -f helm/dim-cluster-values.yaml --version=4.5.0 \
  --set k8sNodeBlockList=null
kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=300s
```

### Handoff

Proceed to [Lab 2.6](06-k8s-control-plane-upgrade.md). Aerospike cluster should remain `Running`; worker nodes should be schedulable.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Force delete bypasses webhook | Never use `--force` in production demo |
| Eviction never completes | Check cluster phase and migration status |

## Not covered here

Control plane upgrade → [Lab 2.6](06-k8s-control-plane-upgrade.md)

## References

- [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance)
