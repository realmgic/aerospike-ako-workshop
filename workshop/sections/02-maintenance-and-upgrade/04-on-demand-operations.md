# Lab 2.4 — On-Demand Operations

| Field | Value |
|-------|-------|
| Lab ID | `2.4` |
| Section | Maintenance & Upgrade |
| EKS cluster | `my-cluster` |
| AKO min version | `4.4.0` |
| Aerospike baseline | dim 3-node in-memory on **8.1.2.x** (from Lab 2.3) |
| Deploy path | both |
| Duration | ~10 min |
| Validation status | `draft` |
| Official docs | [On-demand operations](https://aerospike.com/docs/kubernetes/manage/configure/on-demand-operations) |

## Takeaway

`spec.operations` triggers targeted **PodRestart** (cold) or **WarmRestart** actions without changing `spec.image` or other cluster parameters. AKO allows **at most one** operation entry in the CR at a time.

## Prerequisites

- Lab 2.3 complete — dim cluster Running on **8.1.2.x**
- Cluster spec matches the operation manifests (3-node in-memory dim, `7` CPU / `57Gi`, EBS workdir):

```bash
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.spec.image}{"\n"}'
kubectl -n aerospike get pods
```

**Expected:** Image `aerospike/aerospike-server-enterprise:8.1.2.0`; 3/3 pods `Running`; phase `Completed`.

## Background

| Operation | `kind` | Effect |
|-----------|--------|--------|
| Cold restart | `PodRestart` | Pod deleted and recreated; process exits fully |
| Warm restart | `WarmRestart` | Aerospike process reloads in place; **database node uptime resets**, **pod uptime does not** |

Both manifests carry the full dim cluster spec plus a single `operations` entry. Optional `podList` scopes the operation to named pods; omit it to affect all pods (workshop default).

Reference manifests:

- [manifests/pod-restart-op.yaml](../../manifests/pod-restart-op.yaml) — `PodRestart` / `pod-restart-1`
- [manifests/pod-warm-restart-op.yaml](../../manifests/pod-warm-restart-op.yaml) — `WarmRestart` / `warm-restart-1`

---

## Part 1 — PodRestart (cold restart)

### Path A — kubectl

```bash
kubectl apply -f manifests/pod-restart-op.yaml
kubectl -n aerospike get pods -w
kubectl -n aerospike describe aerospikecluster aerocluster | grep -A10 Operations
```

**Expected:** Pods restart sequentially; operation status progresses to complete in the CR; cluster phase returns `Completed`.

### Path B — Helm

```bash
helm upgrade aerocluster aerospike/aerospike-cluster \
  -n aerospike -f helm/pod-restart-op-values.yaml --version="${AKO_VERSION_START}"
kubectl -n aerospike get pods -w
```

---

## Part 2 — WarmRestart

Wait until Part 1 completes (`kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}'` → `Completed`).

Apply the warm-restart manifest (replaces the operation `kind` / `id` in the same CR):

### Path A — kubectl

```bash
kubectl apply -f manifests/pod-warm-restart-op.yaml
kubectl -n aerospike get pods -w
kubectl -n aerospike describe aerospikecluster aerocluster | grep -A10 Operations
```

**Expected:** Warm restart runs on all pods; pods are **not** deleted (contrast with Part 1); cluster stays available. **Database node uptime** (Aerospike) resets; **pod uptime** (`status.startTime`) does not — the clearest signal that the process reloaded inside the existing pod.

### Path B — Helm

```bash
helm upgrade aerocluster aerospike/aerospike-cluster \
  -n aerospike -f helm/pod-warm-restart-op-values.yaml --version="${AKO_VERSION_START}"
kubectl -n aerospike get pods -w
```

### Optional — single-pod scope

To warm-restart one pod only, add `podList` under `operations` (see [AKO config reference](https://aerospike.com/docs/kubernetes/reference/config-reference)):

```yaml
operations:
  - kind: WarmRestart
    id: warm-restart-1
    podList:
      - aerocluster-0-0
```

---

## Verify (pass/fail)

After each part:

```bash
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'
kubectl -n aerospike get pods -o wide
```

**Pass:** Phase `Completed`; 3/3 pods `Running`.

Compare restart behavior:

```bash
# PodRestart: container start time resets (pod may have new UID)
kubectl -n aerospike get pod aerocluster-0-0 -o jsonpath='{.status.startTime}{"\n"}{.status.containerStatuses[?(@.name=="aerospike-server")].restartCount}{"\n"}'
```

After **PodRestart**, expect recent `startTime` and/or elevated `restartCount`. After **WarmRestart**, the pod object is unchanged (`startTime` and UID the same) while Aerospike reloads in place.

After Part 2, compare **pod uptime** vs **database node uptime** on one node:

```bash
# Pod uptime — should be unchanged from before WarmRestart (same startTime)
kubectl -n aerospike get pod aerocluster-0-0 -o jsonpath='{.metadata.name}{" startTime="}{.status.startTime}{"\n"}'

# Database node uptime — should reset (low seconds) after WarmRestart
kubectl exec -n aerospike aerocluster-0-0 -c aerospike-server -- \
  asinfo -v 'statistics' | tr ';' '\n' | grep '^uptime'
```

**Pass (WarmRestart):** `startTime` on the pod is old; `uptime` from `asinfo` is recently reset (near zero compared to pre-operation value).

## Observe

- **PodRestart** vs **WarmRestart** — cold deletes the pod; warm keeps the pod running
- **WarmRestart:** Aerospike **node uptime** resets; Kubernetes **pod uptime** (`startTime`) does not — process reload inside the same pod
- Difference from image upgrade ([Lab 2.3](03-upgrade-aerospike-db.md)) — operations do not change `spec.image`
- Only one `spec.operations` entry allowed at a time; apply the next manifest after the prior operation completes
- Operator logs show operation reconciliation

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Operation stuck / not starting | Confirm prior operation finished; CR has only one `operations` entry |
| Apply rejected after Part 1 | Wait for phase `Completed` before applying warm-restart manifest |
| Cluster spec drift | Manifests match post-2.3 dim cluster (`8.1.2.0`, in-memory namespace, `57Gi`) — re-run [Lab 2.3](03-upgrade-aerospike-db.md) prep if needed |

## Handoff

Proceed to [Lab 2.5](05-k8s-node-maintenance.md).

## References

- [manifests/pod-restart-op.yaml](../../manifests/pod-restart-op.yaml)
- [manifests/pod-warm-restart-op.yaml](../../manifests/pod-warm-restart-op.yaml)
- [On-demand operations](https://aerospike.com/docs/kubernetes/manage/configure/on-demand-operations)
