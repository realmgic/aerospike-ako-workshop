# Lab 2.5 — K8s Worker Node Maintenance (Karpenter)

| Field | Value |
|-------|-------|
| Lab ID | `2.5` |
| Section | Maintenance & Upgrade |
| EKS cluster | `my-cluster` |
| Node provisioning | **Karpenter** |
| AKO min version | `4.4.0` |
| Duration | ~25 min (+ optional ~15 min add-on) |
| Validation status | `draft` |
| Official docs | [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance) |

## Takeaway

On Karpenter, use **drain + AKO safe eviction** for planned node maintenance. Safe eviction blocks drain **only while Aerospike migration is active**; without active migration, drain cordons the node. **local-ssd PVCs** pin pods to the node until claims are cleared — node termination triggers the PVC cleanup controller and pod rescheduling on a replacement NodeClaim.

For **Karpenter-initiated** disruption (consolidation, drift/AMI rollouts), pair safe eviction with a correctly sized **`terminationGracePeriod`** — do not rely on `k8sNodeBlockList` ([AKO #305](https://github.com/aerospike/aerospike-kubernetes-operator/issues/305)).

## Prerequisites

- `NODE_PROVISIONING=karpenter`
- Lab 2.4 complete — cluster on **8.1.2.x** (device storage default)
- [Safe pod eviction enabled](05-k8s-node-maintenance.md#enable-safe-pod-eviction-required) — **disabled by default**; OLM path must patch `ENABLE_SAFE_POD_EVICTION=true`
- NodePool `terminationGracePeriod` ≥600s (configured in bootstrap)
- Cluster `Running`

## Phase 0 — Prepare lab

Same as the [eksctl guide](05-k8s-node-maintenance.md#phase-0--prepare-lab):

```bash
./scripts/labs/prepare-lab.sh 2.5
```

## Phase 1 — Seed data

Same as the [eksctl guide](05-k8s-node-maintenance.md#phase-1--seed-data-make-migration-visible) — Option A (`load-data.sh`) or Option B (`prepare-lab.sh 2.5 --load-data`).

## Phase 2 — Drain + observe (primary)

AKO safe eviction applies regardless of node provisioner. Follow [Phase 2 in the main guide](05-k8s-node-maintenance.md#phase-2--drain--observe-core-demo) — capture `$NODE`, drain, observe migration, retry after CR `Completed`.

**Pass during active migration:**

- Terminal A shows webhook denial for the Aerospike pod
- CR phase **`InProgress`**
- asadm shows non-zero migrate stats
- Pod on `$NODE` may be `Running` or `Terminating`

Optional: [Force visible drain block](05-k8s-node-maintenance.md#2-optional--force-visible-drain-block-instructor--demo) if migration finishes too fast.

## Phase 3 — PVC pinning observe

Same as the [eksctl guide Phase 3](05-k8s-node-maintenance.md#phase-3--pvc-pinning-observe) — after drain you may see **Path A** (local-ssd PVC node affinity keeps the pod on the cordoned node) or **Path B** (AKO `localStorageClasses` deleted claims during drain; pod already `Running` elsewhere).

## Phase 4 — Node termination + PVC cleanup

Replace the drained worker via Karpenter NodeClaim lifecycle. The eksctl [Phase 4 optional same-AZ scale-up](05-k8s-node-maintenance.md#4-optional--add-same-az-capacity-before-termination-eksctl) is not needed here — deleting the NodeClaim provisions replacement capacity in the same zone automatically.

1. Delete the NodeClaim for `$NODE`:

   ```bash
   CLAIM=$(kubectl get nodeclaims -o jsonpath="{.items[?(@.status.nodeName==\"${NODE}\")].metadata.name}")
   kubectl delete nodeclaim "$CLAIM"
   ```

2. Watch NodeClaim termination and replacement:

   ```bash
   kubectl get nodeclaims,nodes -w
   ```

3. Watch PVC cleanup and pod reschedule:

   ```bash
   kubectl -n kube-system logs deploy/local-volume-node-cleanup-controller -f
   kubectl -n aerospike get pvc -w
   kubectl -n aerospike get pod -l aerospike.com/cr=aerocluster -o wide -w
   ```

**Pass:** Orphaned local-ssd PVCs removed; replacement node `Ready`; `aerocluster-0-0` pod `Running` on new node; CR `Completed`.

Ctrl+C once replacement is stable. `nvme-bootstrap` initializes NVMe on the new instance (Lab 0.5).

## Steps — Observe Karpenter disruption (optional demo)

After Phase 4, optionally show broader Karpenter node lifecycle:

1. Watch NodeClaim termination:

   ```bash
   kubectl get nodeclaims,nodes -w
   ```

2. Optionally delete a NodeClaim to trigger replacement:

   ```bash
   CLAIM=$(kubectl get nodeclaims -o jsonpath='{.items[0].metadata.name}')
   kubectl delete nodeclaim "$CLAIM"
   ```

   **Expected:** Karpenter provisions replacement i8g node; `nvme-bootstrap` DaemonSet initializes NVMe.

3. Discuss NodePool disruption and grace settings:

   ```bash
   kubectl get nodepool "${KARPENTER_NODEPOOL_NAME}" -o yaml | grep -E 'disruption:|terminationGracePeriod|expireAfter'
   ```

   Note `terminationGracePeriod` — covered in the [add-on](#terminationgraceperiod--workshop-baseline-and-production-sizing) below.

   **Do not** force-delete nodes — bypasses AKO safe eviction webhook.

## Add-on — Graduating from `do-not-disrupt` to Karpenter-native disruption (~15 min)

> **Instructor-led discussion.** Run after the drain demo when the audience manages Karpenter + Aerospike in production and is planning to allow voluntary Karpenter disruption (consolidation, drift, AMI rollouts). No live cluster changes required unless you choose to demo consolidation policy inspection.

Many teams start with **`karpenter.sh/do-not-disrupt`** on Aerospike pods to block Karpenter from voluntarily picking those nodes for consolidation or drift. That is a common, conservative **Phase 1** — but it is not a long-term strategy: it blocks cost optimization, AMI drift, and automated node lifecycle. The goal of this add-on is to show how to **graduate safely** using the same AKO protections demonstrated in the drain path above.

### Three layers — complementary, not interchangeable

| Layer | Mechanism | Blocks what | Does **not** block |
|-------|-----------|-------------|-------------------|
| **1 — Karpenter opt-out** | `karpenter.sh/do-not-disrupt` on pod (or node) | Voluntary consolidation and drift | Expiration, Spot interruption, manual `kubectl delete node`, node repair |
| **2 — AKO safe eviction** | `safePodEviction.enable=true` (operator webhook) | Premature **API eviction** until Aerospike migration completes | Karpenter **force-delete** after grace period elapses |
| **3 — Karpenter force ceiling** | NodePool `spec.template.spec.terminationGracePeriod` | *(Does not block — sets max wait before force termination)* | N/A — this is the upper bound on how long layer 2 has to finish |

AKO's [node maintenance docs](https://aerospike.com/docs/kubernetes/manage/node-maintenance) warn that Karpenter uses a **Drain → Wait → Force-Delete** flow: the safe eviction webhook can deny the initial eviction, but Karpenter will **force-terminate** pods once `terminationGracePeriod` expires. Size that period for your **worst-case Aerospike migration**, not for a typical drain.

```mermaid
sequenceDiagram
    participant K as Karpenter
    participant API as Kubernetes API
    participant AKO as AKO safe eviction webhook
    participant AS as Aerospike pod

    K->>API: Evict pod (consolidation / drift / drain)
    API->>AKO: Validate eviction
    AKO-->>API: Deny (migration in progress)
    Note over AS: AKO migrates data; CR → Completed
    K->>API: Retry eviction
    API->>AKO: Validate eviction
    AKO-->>API: Allow
    API->>AS: Pod terminates gracefully

    Note over K,AS: If migration exceeds terminationGracePeriod
    K->>AS: Force-delete pod (bypasses webhook)
```

### `terminationGracePeriod` — workshop baseline and production sizing

Workshop NodePools set **`terminationGracePeriod: 600s`** (10 minutes) at bootstrap:

```yaml
# workshop/scripts/setup/karpenter/02-nodepool-aerospike-zone.yaml
spec:
  template:
    spec:
      expireAfter: 720h
      terminationGracePeriod: 600s   # max wait before Karpenter force-deletes
  disruption:
    consolidationPolicy: WhenEmpty   # or Off during live demos
    consolidateAfter: 30m
```

Inspect the live value on any Aerospike NodePool:

```bash
kubectl get nodepool -l workshop.aerospike.com/workload=aerospike \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.terminationGracePeriod}{"\n"}{end}'
```

**How to think about sizing:**

| Factor | Guidance |
|--------|----------|
| **What it controls** | Maximum time Karpenter waits on a blocking eviction (including AKO-denied evictions) before **force-deleting** the pod |
| **What it does *not* control** | AKO `safePodEviction.timeoutSeconds` — that is per-request webhook response time, not migration budget |
| **Workshop default (600s)** | Reasonable starting point for a 3-node cluster; validate in **your** environment |
| **Production rule of thumb** | Set ≥ measured P99 migration time under load + pod startup/index rebuild buffer; err high for local-storage / large-index clusters |
| **Pair with `expireAfter`** | If pods carry `do-not-disrupt`, Karpenter docs require `terminationGracePeriod` when using `expireAfter` — otherwise nodes can stick indefinitely |

**Sizing exercise (discussion, not a lab step):**

1. Run a controlled drain (primary path above) and time CR `Completed`:

   ```bash
   time kubectl -n aerospike wait --for=jsonpath='{.status.phase}'=Completed \
     aerospikecluster/aerocluster --timeout=900s
   ```

2. Add headroom (e.g. 2× measured migration) for concurrent consolidations or degraded nodes.
3. Patch NodePool only after review — example (do **not** run live in class without a maintenance window):

   ```bash
   kubectl patch nodepool "${KARPENTER_NODEPOOL_NAME}-us-east-1c" --type=merge \
     -p '{"spec":{"template":{"spec":{"terminationGracePeriod":"900s"}}}}'
   ```

### Graduation path — Phase 1 → Phase 3

| Phase | Configuration | When to use |
|-------|---------------|-------------|
| **1 — Block voluntary disruption** | `karpenter.sh/do-not-disrupt: "true"` on Aerospike pods; `KARPENTER_CONSOLIDATION=Off` or `WhenEmpty` + long `consolidateAfter`; monitoring | Initial Karpenter adoption; validating migration behavior |
| **2 — Enable AKO protection** | `safePodEviction.enable=true`; `terminationGracePeriod` sized from measurements; keep `do-not-disrupt` until Phase 2 is validated | Before removing annotations — safe eviction alone is insufficient without grace period headroom |
| **3 — Allow selective disruption** | Remove `do-not-disrupt` from Aerospike pods; enable `consolidationPolicy: WhenEmpty`; tune `consolidateAfter`; use **manual drain** for planned maintenance | Steady state — cost optimization + AMI drift with AKO migration gating |

**Phase 1 — audit current protection (read-only):**

```bash
# Pods opted out of voluntary Karpenter disruption
kubectl get pods -n aerospike -l aerospike.com/cr=aerocluster \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.karpenter\.sh/do-not-disrupt}{"\n"}{end}'

# NodePool disruption + grace settings
kubectl get nodepool -o custom-columns=\
NAME:.metadata.name,\
CONSOLIDATION:.spec.disruption.consolidationPolicy,\
CONSOLIDATE_AFTER:.spec.disruption.consolidateAfter,\
GRACE:.spec.template.spec.terminationGracePeriod,\
EXPIRE:.spec.template.spec.expireAfter
```

**Phase 3 — controlled rollout checklist (production, not live demo):**

1. Confirm `ENABLE_SAFE_POD_EVICTION=true` on operator (OLM: subscription env; Helm: `safePodEviction.enable=true`) and eviction webhook Ready — see [main guide](05-k8s-node-maintenance.md#enable-safe-pod-eviction-required).
2. Measure worst-case migration time; set `terminationGracePeriod` accordingly.
3. Enable `WhenEmpty` consolidation on one NodePool; keep `do-not-disrupt` on other pools until validated.
4. Watch for `aerospike.com/eviction-blocked` and CR phase during first consolidation events.
5. Alert on force-delete / unexpected pod restarts — indicates grace period too short.
6. **Planned maintenance** (patching, hardware, node retirement): always prefer **cordon + drain** (primary path above), not reliance on consolidation.

### What `do-not-disrupt` does not protect against

Even with annotations, these can still terminate nodes — safe eviction + grace period still apply, but Karpenter will not skip the event:

| Event | Blocked by `do-not-disrupt`? | Mitigation |
|-------|------------------------------|------------|
| Consolidation / drift | Yes (voluntary) | Remove annotation in Phase 3 when ready |
| `expireAfter` node expiry | **No** | Size `terminationGracePeriod`; plan replacement |
| Spot / scheduled interruption | **No** | On-demand capacity; rack awareness |
| Manual `kubectl delete node` | **No** | Use drain; never `--force` |
| AMI drift (EC2NodeClass update) | Partially — nodes with annotated pods excluded unless grace period applies | Coordinate AMI rollouts with maintenance windows |

Workshop EC2NodeClass tracks **`al2023@latest`** (`01-ec2nodeclass-i8g.yaml`). Production AMI rollouts should be treated as **planned maintenance**: drain nodes hosting Aerospike pods, or validate Phase 3 protections before allowing drift.

### Key messages for the customer conversation

- **`do-not-disrupt` is a valid safety rail**, not an anti-pattern — but plan to graduate.
- **Safe eviction and `do-not-disrupt` are complementary** — neither replaces the other.
- **`terminationGracePeriod` is the force-delete ceiling** — if migration exceeds it, Aerospike pods can be force-deleted and you risk reindex/cold-start penalties.
- **Planned maintenance → drain**; **automated lifecycle → safe eviction + grace period + gradual consolidation enablement**.

## Verify (pass/fail)

**Pass:** Webhook denied drain during active migration; node cordoned after CR `Completed`; local PVCs cleaned up after node replacement; Aerospike pods `Running` on other nodes. No `k8sNodeBlockList` applied.

## What NOT to demo on Karpenter

| Technique | Status |
|-----------|--------|
| `kubectl drain` + safe eviction | **Supported** |
| `k8sNodeBlockList` | **Unsupported** — eksctl path only |
| `kubectl delete node --force` | **Never** — bypasses webhook |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Drain not blocked | Migration may have finished; use [Phase 2 optional](05-k8s-node-maintenance.md#2-optional--force-visible-drain-block-instructor--demo) |
| Pod stuck on cordoned node | Expected with local PVC — proceed to Phase 4 |
| PVC not cleaned up after node delete | Check cleanup controller logs; wait 60s |
| Node not terminating after drain | Check PDB; verify terminationGracePeriod |
| Replacement node missing NVMe | Verify `nvme-bootstrap` DaemonSet Ready |
| Consolidation removes nodes mid-lab | Set `KARPENTER_CONSOLIDATION=Off` |
| Pod force-deleted during consolidation | `terminationGracePeriod` too short — increase and re-measure migration time |
| Node stuck after `do-not-disrupt` + `expireAfter` | Ensure `terminationGracePeriod` is set ([Karpenter disruption docs](https://karpenter.sh/docs/concepts/disruption/)) |
| Over-use of `do-not-disrupt` (>~30% of pods) | Audit quarterly; blocks consolidation and AMI drift efficiency |

## References

- [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance)
- [AKO #305 — blocklist + Karpenter](https://github.com/aerospike/aerospike-kubernetes-operator/issues/305)
- [Karpenter — Disruption](https://karpenter.sh/docs/concepts/disruption/)
