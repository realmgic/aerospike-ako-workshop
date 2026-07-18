# Lab 2.5 — K8s Worker Node Maintenance

| Field | Value |
|-------|-------|
| Lab ID | `2.5` |
| Section | Maintenance & Upgrade |
| EKS cluster | `my-cluster` |
| AKO min version | `4.5.0` |
| Aerospike baseline | 3-node device storage on local-ssd (**8.1.2.x**); in-memory with `--dim` |
| Deploy path | both |
| Node provisioning | both (blocklist **eksctl only**) |
| Duration | ~25 min |
| Validation status | `draft` |
| Official docs | [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance) |

## Takeaway

AKO's safe pod eviction webhook blocks `kubectl drain` while data migrates. The Aerospike pod **stays Running on the node** until migration completes and the `AerospikeCluster` returns to `Completed` — only then does drain succeed.

## Prerequisites

- Lab 2.4 complete (DB upgrade to **8.1.2.x**; implies AKO **4.5.0**)
- [Safe pod eviction enabled](#enable-safe-pod-eviction-required) on the operator — **disabled by default** in AKO ([docs](https://aerospike.com/docs/kubernetes/manage/node-maintenance/#safe-pod-eviction-webhook))
- 3-node cluster `Running`; phase `Completed` (device storage by default)

## Enable safe pod eviction (required)

AKO's [safe pod eviction webhook](https://aerospike.com/docs/kubernetes/manage/node-maintenance/#safe-pod-eviction-webhook) intercepts pod eviction API calls from `kubectl drain`. When eviction is blocked, the webhook sets `aerospike.com/eviction-blocked` on the pod and AKO migrates data before drain can succeed.

**This feature is disabled by default.** Without it, Phase 2 drain completes immediately — no blocked eviction, no annotation, no visible migration window.

**Workshop defaults:**

| Path | Enabled at install? | Action before Lab 2.5 |
|------|---------------------|------------------------|
| **B — Helm** | Yes — `safePodEviction.enable=true` in [helm/operator-values.yaml](../../helm/operator-values.yaml) (Lab 0.3) | Verify below; re-apply values if AKO was upgraded without `-f helm/operator-values.yaml` |
| **A — OLM** | **No** — not set by `./scripts/setup/03-install-ako.sh` | Patch subscription with `ENABLE_SAFE_POD_EVICTION=true` (below) |

### Path B — Helm

Re-apply workshop operator values (safe after Lab 2.2 AKO upgrades):

```bash
source scripts/env/workshop.env
helm upgrade "${HELM_OPERATOR_RELEASE}" aerospike/aerospike-kubernetes-operator \
  -n "${OPERATOR_NAMESPACE}" \
  --reuse-values \
  -f helm/operator-values.yaml
```

Or set explicitly per [Aerospike docs](https://aerospike.com/docs/kubernetes/manage/node-maintenance/#enabling-safe-pod-eviction):

```yaml
safePodEviction:
  enable: "true"
  timeoutSeconds: "20"   # webhook response wait per eviction request, not migration budget
```

### Path A — OLM

Patch the Subscription to set `ENABLE_SAFE_POD_EVICTION=true` ([Aerospike docs](https://aerospike.com/docs/kubernetes/manage/node-maintenance/#enabling-safe-pod-eviction)):

```bash
kubectl -n operators patch subscription aerospike-kubernetes-operator \
  --type='merge' \
  -p '{"spec":{"config":{"env":[{"name":"ENABLE_SAFE_POD_EVICTION","value":"true"}]}}}'
```

Wait for OLM to reconcile and the operator deployment to roll out.

### Verify

```bash
kubectl -n operators get deployment aerospike-operator-controller-manager \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"="}{.value}{"\n"}{end}' \
  | grep ENABLE_SAFE_POD_EVICTION

kubectl get validatingwebhookconfiguration | grep aerospikeeviction

kubectl -n operators rollout status deployment/aerospike-operator-controller-manager --timeout=120s
```

**Expected:** `ENABLE_SAFE_POD_EVICTION=true`; eviction validating webhook listed; controller Ready.

## Phase 0 — Prepare lab

Tears down existing `aerocluster` if present and deploys fresh maintenance baseline (clears Lab 2.3 operations):

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

An empty cluster migrates too fast to observe (especially in-memory — use `--dim` or pre-load data). Load records first using the **`app`** user (`read` + `write` roles; secret `auth-app-secret` / password `app123`), defined in the maintenance baseline manifest:

```bash
./scripts/labs/load-data.sh
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

# Safe eviction annotation on blocked pod(s) on the drained node
kubectl -n aerospike get pod -l aerospike.com/cr=aerocluster --field-selector spec.nodeName="$NODE" \
  -o custom-columns='NAME:.metadata.name,EVICTION-BLOCKED:.metadata.annotations.aerospike\.com/eviction-blocked'

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

1. Edit `manifests/disk-node-blocklist.yaml` (or `manifests/node-blocklist.yaml` with `--dim`) — set `k8sNodeBlockList` to `$NODE`.
2. Apply and watch (pod stays on node until CR `Completed`):

   ```bash
   kubectl apply -f manifests/disk-node-blocklist.yaml
   kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'
   kubectl -n aerospike get pod -o wide --field-selector spec.nodeName="$NODE" -w
   ```

   Ctrl+C once pods have moved off `$NODE`.

3. Wait for migration:

   ```bash
   kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=900s
   ```

### Path B — Helm

1. Edit `helm/disk-node-blocklist-values.yaml` (or `helm/node-blocklist-values.yaml` with `--dim`) — set `k8sNodeBlockList` to `$NODE`.
2. Apply and watch:

   ```bash
   helm upgrade aerocluster aerospike/aerospike-cluster \
     -n aerospike -f helm/disk-node-blocklist-values.yaml --version="${AKO_VERSION_START}"
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
  -n aerospike -f helm/disk-cluster-maintenance-values.yaml --version="${AKO_VERSION_START}" \
  --set k8sNodeBlockList=null
kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed aerospikecluster/aerocluster --timeout=900s
```

### Handoff

Proceed to [Lab 2.6](06-k8s-control-plane-upgrade.md). Aerospike cluster should remain `Running`; worker nodes should be schedulable.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Migration completes too fast to observe | Increase `MIGRATION_LOAD_RECORDS` (e.g. `8000000`) and re-run load script |
| local-ssd PVC Pending | Re-run `./scripts/setup/08-validate-environment.sh`; confirm baseline local-ssd PVs |
| No `eviction-blocked` annotation | Confirm `ENABLE_SAFE_POD_EVICTION=true` on operator deployment; Helm: re-apply `helm/operator-values.yaml`; OLM: patch subscription env; check eviction webhook Ready |
| CR stays `InProgress` | Check operator logs; wait for migrate stats to reach zero |
| Force delete bypasses webhook | Never use `--force` in production demo |
| Blocklist changes cluster profile | Use updated blocklist manifest matching your storage (`disk-node-blocklist.yaml` default) |

## Not covered here

- Karpenter voluntary disruption, `do-not-disrupt`, and `terminationGracePeriod` → [Karpenter lab add-on](05-k8s-node-maintenance-karpenter.md#add-on--graduating-from-do-not-disrupt-to-karpenter-native-disruption-15-min)
- Control plane upgrade → [Lab 2.6](06-k8s-control-plane-upgrade.md)

## References

- [manifests/disk-cluster-maintenance.yaml](../../manifests/disk-cluster-maintenance.yaml)
- [manifests/disk-node-blocklist.yaml](../../manifests/disk-node-blocklist.yaml)
- [scripts/labs/load-data.sh](../../scripts/labs/load-data.sh)
- [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance)
