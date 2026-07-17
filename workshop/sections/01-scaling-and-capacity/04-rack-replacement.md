# Lab 1.4 — Rack Replacement

| Field | Value |
|-------|-------|
| Lab ID | `1.4` |
| Section | Scaling & Capacity |
| EKS cluster | `my-cluster` |
| Aerospike cluster | `aerocluster` |
| AKO min version | `4.2.0` |
| Aerospike baseline | rack v1 on i8g.2xlarge, then vertical 2× scale via replacement |
| Deploy path | both |
| Node provisioning | both |
| Duration | ~30 min |
| Validation status | `draft` |
| Official docs | [Scaling — rack replacement](https://aerospike.com/docs/kubernetes/manage/configure/scaling) |

## Takeaway

Replacing rack IDs (remove racks 1+2, add racks 3+4) scales vertically to the same **2× profile as Lab 1.3 v2** — but via **rack replacement** instead of revision. During migration, old and new racks run concurrently.

**Contrast with Lab 1.3:** revision keeps rack IDs 1+2; replacement introduces new rack IDs 3+4 (stronger illustration of rack-ID change + client impact).

## Prerequisites

- Section 0 storage layer complete
- **Does not require Lab 1.3 v2** — this lab is standalone

## Node requirements

| Item | Value |
|------|-------|
| Phase 1 | `i8g.2xlarge` × 4 — `workshop.aerospike.com/node-pool=baseline` |
| Phase 2 | `i8g.4xlarge` × 4 — `workshop.aerospike.com/node-pool=vertical` **added alongside** 2xl |
| Phase 3 | Pods on vertical / 4xl only |
| Reset | **Light** at lab start (database only; provisions baseline 2xl pool) |

During Phase 2, both pools may coexist (8 nodes total) — same quota note as Lab 1.3.

## Phase 0 — Light reset + baseline 2xl nodes

```bash
./scripts/labs/prepare-lab.sh 1.4
```

**Expected:** Database torn down; 4× `i8g.2xlarge` Ready with `node-pool=baseline`.

## Phase 1 — Deploy v1 baseline (racks 1+2 on 2xl)

```bash
./scripts/labs/deploy-rack-cluster.sh       # Path A
# or
./scripts/labs/deploy-rack-cluster-helm.sh  # Path B
```

**Expected:** `aerocluster-1-v1-*`, `aerocluster-2-v1-*` on `baseline` / `i8g.2xlarge`; memory `57Gi`; CR `Completed`.

Verify:

```bash
./scripts/labs/lab-nodes.sh 1.4 validate
kubectl -n aerospike get pods -o wide
kubectl -n aerospike get pod aerocluster-1-v1-0 -o jsonpath='{.spec.nodeSelector}{"\n"}'
```

**Pass:** `nodeSelector` shows `baseline`; pods on `i8g.2xlarge` only.

## Phase 2 — Add vertical node pool (2× instance size)

```bash
./scripts/labs/lab-nodes.sh 1.4 ensure --vertical
./scripts/labs/lab-nodes.sh 1.4 validate --vertical
kubectl get nodes -L workshop.aerospike.com/node-pool,node.kubernetes.io/instance-type
```

**Expected:** 4× `i8g.4xlarge` Ready with `node-pool=vertical`; baseline pool remains idle.

## Phase 3 — Rack replacement + vertical scale (racks 3+4 replace 1+2)

The replacement manifest removes racks 1+2 and defines racks 3+4 only, with the same vertical profile as Lab 1.3 v2 (`15` CPU / `115Gi`, dual `local-ssd` block devices, `nodeSelector: vertical`).

### Path A — kubectl

```bash
source scripts/env/workshop.env
envsubst '$NODE_ZONE_A $NODE_ZONE_B' < manifests/rack-cluster-replacement.yaml | kubectl apply -f -
kubectl -n aerospike get pods -w
```

**Expected:** Period with racks 1–4 coexisting; rack 1+2 pods terminate after migration; new pods `aerocluster-3-v1-*`, `aerocluster-4-v1-*` on vertical nodes.

### Path B — Helm

```bash
source scripts/env/workshop.env
envsubst '$NODE_ZONE_A $NODE_ZONE_B' < helm/rack-cluster-replacement-values.yaml | \
  helm upgrade aerocluster aerospike/aerospike-cluster \
  -n aerospike -f - --version=4.2.0
kubectl -n aerospike get pods -w
```

## Verify (pass/fail)

```bash
./scripts/labs/lab-nodes.sh 1.4 validate --vertical
kubectl -n aerospike get pods -o wide
kubectl -n aerospike get pod aerocluster-3-v1-0 -o jsonpath='{.spec.nodeSelector}{"\n"}{.spec.containers[?(@.name=="aerospike-server")].resources.limits.memory}{"\n"}'
kubectl -n aerospike get pvc -o wide
```

**Pass:** No rack 1 or 2 pods; only racks **3+4** on `vertical` / `i8g.4xlarge`; memory `115Gi`; 2 block PVCs per pod; CR `Completed`.

## Observe

- Two rack sets running concurrently during migration
- Rack ID change (1+2 → 3+4) vs revision (Lab 1.3 keeps IDs 1+2) — instructor discussion point
- Same end-state resources as Lab 1.3 v2, different AKO mechanism

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Replacement pods Pending | Verify vertical pool: `lab-nodes.sh 1.4 validate --vertical` |
| Missing node-pool labels | Re-run `ensure` / `ensure --vertical` |
| local-ssd PVC exhaustion on 4xl | 2 PVCs per pod; check PV count per node |

## Not covered here

Rack revision → [Lab 1.3](03-rack-revision.md)

## Teardown / handoff

`./scripts/reset-cluster.sh --yes` before Section 2 maintenance labs, or when done for the day.

## References

- [Scaling](https://aerospike.com/docs/kubernetes/manage/configure/scaling)
