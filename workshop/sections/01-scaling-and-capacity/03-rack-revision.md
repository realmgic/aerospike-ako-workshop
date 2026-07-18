# Lab 1.3 — Vertical Scaling & Rack Revision


| Field              | Value                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------- |
| Lab ID             | `1.3`                                                                                     |
| Section            | Scaling & Capacity                                                                        |
| EKS cluster        | `my-cluster`                                                                              |
| Aerospike cluster  | `aerocluster`                                                                             |
| AKO min version    | `4.2.0`                                                                                   |
| Aerospike baseline | rack v1 block storage on i8g.2xlarge (`baseline` node pool)                               |
| Deploy path        | both                                                                                      |
| Node provisioning  | both                                                                                      |
| Duration           | ~45 min                                                                                   |
| Validation status  | `draft`                                                                                   |
| Official docs      | [Scaling — rack revision](https://aerospike.com/docs/kubernetes/manage/configure/scaling) |




## Takeaway

Vertical scaling combines **node pool locator** (`podSpec.nodeSelector`), larger pod resources, and rack storage revision — AKO migrates data to new local-ssd PVCs on the vertical pool via `revision: v2` **without changing rack IDs**.

## Prerequisites

- Section 0 storage layer complete
- Lab 1.2 complete (Track A → B), or `./scripts/labs/prepare-lab.sh 1.3 --full` for a cold start



## Node requirements


| Item    | Value                                                                                                                                                                   |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 1 | `i8g.2xlarge` × 4 — `${NODEGROUP_NAME}-<zone>` (eksctl) or `${KARPENTER_NODEPOOL_NAME}-<zone>` (Karpenter) — label `workshop.aerospike.com/node-pool=baseline` |
| Phase 2 | `i8g.4xlarge` × 4 — `${NODEGROUP_NAME_VERTICAL}-<zone>` or `${KARPENTER_NODEPOOL_VERTICAL_NAME}-<zone>` — label `workshop.aerospike.com/node-pool=vertical` **added alongside baseline** |
| Reset   | **Light** at lab start (database only; reuses baseline pool)                                                                                                                 |


During Phase 2, both pools coexist (8 nodes total until `./scripts/reset-cluster.sh` before Section 2 or end of day):


| Pool                                                                 | Instance    | Label      | When                                  |
| -------------------------------------------------------------------- | ----------- | ---------- | ------------------------------------- |
| `${NODEGROUP_NAME}-*` / `${KARPENTER_NODEPOOL_NAME}-*` (per zone)     | i8g.2xlarge | `baseline` | Phase 1 — **kept idle** after Phase 2 |
| `${NODEGROUP_NAME_VERTICAL}-*` / `${KARPENTER_NODEPOOL_VERTICAL_NAME}-*` | i8g.4xlarge | `vertical` | Created Phase 2 (one pool per zone)   |




## Phase 0 — Prepare lab

```bash
./scripts/labs/prepare-lab.sh 1.3
```

**Expected:** 4× `i8g.2xlarge` Ready across `${AWS_ZONES}` with `workshop.aerospike.com/node-pool=baseline`. Prep also validates baseline local-ssd PVs (~3 per node, e.g. `OK baseline (i8g.2xlarge): 12 local-ssd PVs`); restarts the provisioner only if PV count is short.

Use `./scripts/labs/prepare-lab.sh 1.3 --full` only for a hard wipe (database + all workload pools).

## Phase 1 — Deploy baseline (rack v1 on baseline / i8g.2xlarge)

```bash
./scripts/labs/deploy-rack-cluster.sh       # Path A
# manual Path A: source scripts/lib/common.sh && source scripts/lib/render-yaml.sh && load_env && \
#   render_workshop_yaml manifests/rack-cluster-v1.yaml | kubectl apply -f -

./scripts/labs/deploy-rack-cluster-helm.sh  # Path B
# applies helm/rack-cluster-v1-values.yaml (zones from AWS_ZONES via load_env)
```

**Expected:** 4 pods on revision `v1`; CR `Completed`; pods pinned to `baseline` pool.

Verify baseline:

```bash
kubectl -n aerospike get pod aerocluster-1-v1-0 -o jsonpath='{.spec.nodeSelector}{"\n"}'
kubectl -n aerospike get pod aerocluster-1-v1-0 -o jsonpath='{.spec.containers[?(@.name=="aerospike-server")].resources.limits.memory}{"\n"}'
kubectl get nodes -l workshop.aerospike.com/node-pool=baseline -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type
```

**Pass:** `nodeSelector` shows `baseline`; memory limit `57Gi`; nodes show `i8g.2xlarge` only.

## Phase 2 — Add vertical node pool (i8g.4xlarge)

```bash
./scripts/labs/lab-nodes.sh 1.3 ensure --vertical
./scripts/labs/lab-nodes.sh 1.3 validate --vertical
kubectl get nodes -L workshop.aerospike.com/node-pool,node.kubernetes.io/instance-type
```

**Expected:** 4× `i8g.4xlarge` Ready in both zones with `node-pool=vertical`; baseline pool remains (4 idle nodes). Pods stay on baseline until Phase 3. `ensure --vertical` validates vertical local-ssd PVs (~6 per 4xl node, e.g. `OK vertical (i8g.4xlarge): 24 local-ssd PVs`); restarts the provisioner only if PV count is short.

**Note:** Ensure EC2 quota covers **8 nodes** during Phase 2 (4× baseline idle + 4× vertical active).

### Karpenter path

The `--vertical` flag applies per-AZ NodePools `${KARPENTER_NODEPOOL_VERTICAL_NAME}-<zone>` for `${NODE_TYPE_VERTICAL}` (baseline per-AZ NodePools unchanged). Watch:

```bash
kubectl get nodeclaims,nodes -w
```



## Phase 3 — Apply rack revision + vertical locator + 2× resources

Change three things together in `rack-cluster-v2-revision.yaml`:

1. **Node pool locator:** `nodeSelector` `baseline` → `vertical`
2. **Rack revision:** `v1` → `v2` (adds `ns2` local-ssd block device)
3. **Pod resources:** `7` CPU / `57Gi` → `15` CPU / `115Gi`



### Path A — kubectl

```bash
./scripts/labs/deploy-rack-cluster-v2-revision.sh
kubectl -n aerospike get pods -w
```

**Expected:** Pods migrate to v2 revision on vertical nodes; resources increase to `15` CPU / `115Gi`; 2 block PVCs per pod.

Manual equivalent (must call `load_env` so `${NODE_ZONE_A}` / `${NODE_ZONE_B}` are exported from `AWS_ZONES` — sourcing `workshop.env` alone is not enough):

```bash
source scripts/lib/common.sh
source scripts/lib/render-yaml.sh
load_env
render_workshop_yaml manifests/rack-cluster-v2-revision.yaml | kubectl apply -f -
```

### Path B — Helm

```bash
./scripts/labs/deploy-rack-cluster-v2-revision-helm.sh
kubectl -n aerospike get pods -w
```



## Verify (pass/fail)

```bash
./scripts/labs/lab-nodes.sh 1.3 validate --vertical
kubectl get nodes -L workshop.aerospike.com/node-pool,node.kubernetes.io/instance-type
kubectl -n aerospike get pods -o wide
kubectl -n aerospike get pod aerocluster-1-v2-0 -o jsonpath='{.spec.nodeSelector}{"\n"}{.spec.containers[?(@.name=="aerospike-server")].resources.limits.memory}{"\n"}'
kubectl -n aerospike get pvc -o wide
```

**Pass:** `nodeSelector` shows `vertical`; memory limit `115Gi`; all pods on v2 revision; nodes `i8g.4xlarge`; 2 `local-ssd` block PVCs per pod bound; CR `Completed`.

## Observe

- Node pool label change (`baseline` → `vertical`) drives pod rescheduling to 4xl nodes
- Pod resource bump triggers rolling restart alongside revision migration
- Second block device (`ns2` at `/dev/data/local2`) appears in namespace config
- Data migration progress in asadm



## Troubleshooting


| Symptom                                                   | Fix                                                                                                                                                                                                                  |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pods Pending after vertical pool add                      | Expected until Phase 3 apply; verify `nodeSelector: baseline` still pins Phase 1 pods                                                                                                                                |
| Pods Pending after revision apply                         | Re-run `lab-nodes.sh 1.3 validate --vertical`; check `kubectl describe pod` for node affinity / PVC binding                                                                                                          |
| Missing `workshop.aerospike.com/node-pool` labels         | Re-run `lab-nodes.sh 1.3 ensure` (baseline) or `ensure --vertical`; for eksctl, labels are patched after scale                                                                                                       |
| local-ssd PVC Pending (4xl)                               | Re-run `./scripts/labs/lab-nodes.sh 1.3 ensure --vertical` (waits for nvme-bootstrap, restarts provisioner only if PV count is short, validates PVs). Verify `kubectl get pv -o custom-columns=NAME:.metadata.name,CLASS:.spec.storageClassName --no-headers \| awk '$2 == "local-ssd"'` — expect ~6×512Gi per i8g.4xlarge node |
| Drain stuck on local-storage pods                         | Expected during migration; wait for AKO                                                                                                                                                                              |
| EC2 quota exceeded during Phase 2                         | Request quota for 8× i8g (4× baseline idle + 4× vertical)                                                                                                                                                            |
| Multi-AZ validation fails on vertical pool                | Re-run `./scripts/labs/lab-nodes.sh 1.3 ensure --vertical` — per-AZ vertical pools guarantee `${MIN_NODES_PER_ZONE}` nodes per zone                                                                                  |
| Webhook: RackConfig Zone cannot be updated / `zone: null` | Rack zones were not rendered — use `./scripts/labs/deploy-rack-cluster-v2-revision.sh` or run `load_env` before `envsubst` (see Phase 3 manual command). Verify rendered YAML has `zone: us-east-1c` (not blank) |

## Not covered here

Rack replacement → [Lab 1.4](04-rack-replacement.md) (standalone — does not require completing this lab's v2 state)

## Teardown / handoff

Lab 1.4 is **standalone** — it light-resets and redeploys v1 baseline independently. You may continue to 1.4 without preserving this cluster state.

## References

- [Scaling](https://aerospike.com/docs/kubernetes/manage/configure/scaling)

