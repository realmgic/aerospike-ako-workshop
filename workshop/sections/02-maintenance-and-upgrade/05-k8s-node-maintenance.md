# Lab 2.5 — K8s Worker Node Maintenance

| Field | Value |
|-------|-------|
| Lab ID | `2.5` |
| Section | Maintenance & Upgrade |
| EKS cluster | `my-cluster` |
| AKO min version | `4.5.0` |
| Aerospike baseline | dim 3-node in-memory on **8.1.2.x** (from Lab 2.3/2.4) |
| Deploy path | both |
| Node provisioning | both (blocklist **eksctl only**) |
| Duration | ~25 min |
| Validation status | `draft` |
| Official docs | [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance) |

## Takeaway

AKO's safe pod eviction webhook blocks `kubectl drain` while data migrates. The Aerospike pod **stays Running on the node** until migration completes and the `AerospikeCluster` returns to `Completed` — only then does drain succeed.

## Prerequisites

- Lab 2.4 complete (on-demand operations; implies AKO **4.5.0** and DB on **8.1.2.x**)
- `safePodEviction.enable=true` on operator (Helm values or OLM config)
- 3-node dim cluster `Running`; phase `Completed`

## Phase 0 — Prepare lab

Re-apply the maintenance baseline (clears `spec.operations` from Lab 2.4):

```bash
./scripts/labs/prepare-lab.sh 2.5
```

Optionally load migration data during prep:

```bash
./scripts/labs/prepare-lab.sh 2.5 --load-data
```

Capture pod placement:

```bash
kubectl -n aerospike get pods -o wide
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}{.spec.image}{"\n"}'
NODE=$(kubectl -n aerospike get pods -o wide --no-headers | awk 'NR==1{print $7}')
echo "Maintenance target node: ${NODE}"
```

**Expected:** 3 pods `Running`; CR phase `Completed`; image `8.1.2.x`; no `spec.operations` in CR.

## Phase 1 — Seed data (make migration visible)

An empty dim cluster migrates too fast to observe. Load records first using the **`app`** user (`read` + `write` roles; secret `auth-app-secret` / password `app123`), defined in the maintenance baseline manifest:

```bash
./scripts/labs/load-dim-migration-data.sh
```

Tunable via env (increase if migration completes too quickly):

| Variable | Default | Purpose |
|----------|---------|---------|
| `MIGRATION_LOAD_RECORDS` | `5000000` | Record count |
| `MIGRATION_LOAD_OBJECT_SIZE` | `1024` | Bytes per object (`-o S1024`) |
| `MIGRATION_LOAD_THREADS` | `4` | asbench threads |

Verify data is present:

```bash
kubectl run -it --rm aerospike-tool-ns -n aerospike --restart=Never \
  --image=aerospike/aerospike-tools:latest -- \
  asinfo -h aerocluster -U app -P app123 -v "namespace/test"
```

**Pass:** Non-zero `objects` and `used-bytes` in namespace `test`.

Skip this phase if you used `prepare-lab.sh 2.5 --load-data`.

## Phase 2 — Drain + observe (core demo)

Use **two terminals**. Terminal A starts drain; Terminal B proves the pod is held on the node while AKO migrates.

### Terminal A — start drain

```bash
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
```

**Expected:** Command blocks or reports eviction denied for the Aerospike pod.

### Terminal B — observe while migration is in flight

Run these while Terminal A is still waiting:

```bash
# Pod still on the node — Running, not Terminating
kubectl -n aerospike get pod -o wide --field-selector spec.nodeName="$NODE"

# CR unstable during migration
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'

# Safe eviction annotation on blocked pod(s)
kubectl get pod -n aerospike -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.aerospike\.com/eviction-blocked}{"\n"}{end}'

# Active migration in Aerospike
kubectl run -it --rm aerospike-tool-migrate -n aerospike --restart=Never \
  --image=aerospike/aerospike-tools:latest -- \
  asadm -h aerocluster -U admin -P admin123 -e "show stat like migrate"
```

**Pass (during migration, before retry):**

- Aerospike pod on `$NODE` still `Running` (not `Terminating`)
- CR phase **`InProgress`**
- `aerospike.com/eviction-blocked` set on the target pod
- asadm shows non-zero migrate tx/rx (or decreasing pending)

Re-run the Terminal B commands every few seconds until CR returns to `Completed`.

## Phase 3 — Complete drain

Once migration finishes:

```bash
kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=900s
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
kubectl -n aerospike get pods -o wide
```

**Pass:** Drain succeeds without `--force`; no Aerospike pods remain on `$NODE`; all pods `Running` on other nodes; CR `Completed`.

## Alternate — k8sNodeBlockList (eksctl path only)

> **Karpenter sessions:** skip this section. Use [05-k8s-node-maintenance-karpenter.md](05-k8s-node-maintenance-karpenter.md) instead. `k8sNodeBlockList` uses node hostname affinity incompatible with Karpenter ([AKO #305](https://github.com/aerospike/aerospike-kubernetes-operator/issues/305)).

Same migration observation pattern, triggered via CR blocklist instead of drain webhook. Data must be loaded (Phase 1) first.

### Path A — kubectl

1. Edit `manifests/node-blocklist.yaml` — set `k8sNodeBlockList` to `$NODE`.
2. Apply and watch (pod stays on node until CR `Completed`):

   ```bash
   kubectl apply -f manifests/node-blocklist.yaml
   kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'
   kubectl -n aerospike get pod -o wide --field-selector spec.nodeName="$NODE" -w
   ```

   Ctrl+C once pods have moved off `$NODE`.

3. Wait for migration:

   ```bash
   kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=900s
   ```

### Path B — Helm

1. Edit `helm/node-blocklist-values.yaml` — set `k8sNodeBlockList` to `$NODE`.
2. Apply and watch:

   ```bash
   helm upgrade aerocluster aerospike/aerospike-cluster \
     -n aerospike -f helm/node-blocklist-values.yaml --version="${AKO_VERSION_START}"
   kubectl -n aerospike get pod -o wide --field-selector spec.nodeName="$NODE" -w
   ```

3. Wait for migration:

   ```bash
   kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=900s
   ```

### Observe (blocklist)

```bash
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.spec.k8sNodeBlockList}{"\n"}'
kubectl -n aerospike get pods -o wide
```

**Expected:** Blocklist contains `$NODE`; pod held on node during `InProgress`; no Aerospike pods on `$NODE` after `Completed`.

## Verify (pass/fail)

```bash
kubectl -n aerospike get pods -o wide
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'
```

**Pass:** All Aerospike pods `Running`; CR `Completed`; maintenance target node has no Aerospike pods (drain path) or blocklist cleared (blocklist path).

## Observe

- Safe eviction webhook denies API eviction until migration completes
- Pod remains on the node during `InProgress` — this is the protection trainees should see
- Blocklist triggers AKO-driven rolling migration (hostname affinity — eksctl only)
- Cluster stays available during migration

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

Skip if only the drain path was demonstrated.

**Path A — kubectl:**

```bash
kubectl -n aerospike patch aerospikecluster aerocluster --type=json \
  -p='[{"op": "remove", "path": "/spec/k8sNodeBlockList"}]'
kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=900s
```

**Path B — Helm:**

```bash
helm upgrade aerocluster aerospike/aerospike-cluster \
  -n aerospike -f helm/dim-cluster-maintenance-values.yaml --version="${AKO_VERSION_START}" \
  --set k8sNodeBlockList=null
kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=900s
```

### Handoff

Proceed to [Lab 2.6](06-k8s-control-plane-upgrade.md). Aerospike cluster should remain `Running`; worker nodes should be schedulable.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Migration completes too fast to observe | Increase `MIGRATION_LOAD_RECORDS` (e.g. `8000000`) and re-run load script |
| No `eviction-blocked` annotation | Confirm `safePodEviction.enable=true`; check operator webhook Ready |
| CR stays `InProgress` | Check operator logs; wait for migrate stats to reach zero |
| Force delete bypasses webhook | Never use `--force` in production demo |
| Blocklist changes cluster profile | Use updated `node-blocklist.yaml` (8.1.2.x / 57Gi) — not legacy 4xl manifest |

## Not covered here

- Karpenter voluntary disruption, `do-not-disrupt`, and `terminationGracePeriod` → [Karpenter lab add-on](05-k8s-node-maintenance-karpenter.md#add-on--graduating-from-do-not-disrupt-to-karpenter-native-disruption-15-min)
- Control plane upgrade → [Lab 2.6](06-k8s-control-plane-upgrade.md)

## References

- [manifests/dim-cluster-maintenance.yaml](../../manifests/dim-cluster-maintenance.yaml)
- [manifests/node-blocklist.yaml](../../manifests/node-blocklist.yaml)
- [scripts/labs/load-dim-migration-data.sh](../../scripts/labs/load-dim-migration-data.sh)
- [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance)
