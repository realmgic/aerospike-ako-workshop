# Lab 0.2 — EKS Cluster Bootstrap (Karpenter)

| Field | Value |
|-------|-------|
| Lab ID | `0.2` |
| Section | Environment Setup |
| EKS cluster | `my-cluster` |
| Node provisioning | **Karpenter** |
| Duration | ~40 min |
| Validation status | `draft` |

## Takeaway

A Karpenter-managed EKS cluster with a **system** managed nodegroup for the controller. **Per-AZ workload NodePools** `${KARPENTER_NODEPOOL_NAME}-<zone>` (4× `i8g.2xlarge` total) are created in step **0.2-nodes** before AKO install. Lab 1.2 Phase 2 adds **`${KARPENTER_NODEPOOL_VERTICAL_NAME}-<zone>`** (vertical pool) alongside the baseline pools.

## Prerequisites

- Lab 0.1 complete
- EC2 key pair in target region
- Quota for **4–8×** `i8g.2xlarge` plus 2× `t3.large` system nodes
- Quota for **4–8×** `i8g.4xlarge` during Lab 1.2 Phase 2 (may run **8 nodes** total with idle baseline pool)
- Helm 3.12+ (controller install)

## Starting state

`NODE_PROVISIONING=karpenter` in [workshop.env.example](../../scripts/env/workshop.env.example).

## Steps

1. Source environment:

   ```bash
   source scripts/env/workshop.env
   export NODE_PROVISIONING=karpenter
   ```

2. Create cluster and install Karpenter controller:

   ```bash
   ./scripts/setup/02-bootstrap-eks.sh
   ```

   **Expected:**
   - eksctl creates cluster + `${KARPENTER_SYSTEM_NODEGROUP}` (2× `${KARPENTER_SYSTEM_NODE_TYPE}`, tainted)
   - Karpenter controller Running in `karpenter` namespace
   - **No** workload nodes yet (system nodes only)

3. Create workload NodePool (step 0.2-nodes):

   ```bash
   ./scripts/setup/02-ensure-workload-nodepool.sh
   ```

   **Expected:** `${NODE_COUNT}`× `${NODE_TYPE}` workload nodes Ready across `${AWS_ZONES}` (≥ `${MIN_NODES_PER_ZONE}` per zone).

4. Confirm controller:

   ```bash
   kubectl -n karpenter get deploy karpenter
   kubectl get nodes
   ```

   **Expected:** Karpenter Ready; `${NODE_COUNT}` workload nodes plus system nodes.

5. Confirm namespace:

   ```bash
   kubectl get namespace aerospike
   ```

## Verify (pass/fail)

```bash
kubectl -n karpenter get deploy karpenter
kubectl get nodes
```

**Pass:** Karpenter Ready; `${NODE_COUNT}` workload nodes Ready (per-AZ NodePools `${KARPENTER_NODEPOOL_NAME}-*`).

Reference config: [clusters/main-cluster-karpenter.yaml](../../clusters/main-cluster-karpenter.yaml)

## Observe

- System nodes carry taint `role=system:NoSchedule` — OLM and AKO schedule on untainted workload nodes
- Per-AZ workload NodePools applied in step **0.2-nodes**; Lab 1.1 re-ensures after full reset via `prepare-lab.sh 1.1`

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Controller Pending | Ensure system MNG exists and tolerations match |
| No NodeClaims in Lab 1.1 | Check controller logs; verify subnet/SG discovery tags |

## Instructor notes

- Set `KARPENTER_CONSOLIDATION=Off` during class to limit consolidation churn
- Lab 2.6 upgrade-lab cluster stays on **eksctl MNG** — not this path

## Not covered here

eksctl managed nodegroup path → [02-eks-cluster.md](02-eks-cluster.md)

## References

- [Karpenter on AWS](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
- [AKO scaling — Karpenter + local volumes](https://aerospike.com/docs/kubernetes/manage/configure/scaling)
