# Lab 0.2 — EKS Cluster Bootstrap

| Field | Value |
|-------|-------|
| Lab ID | `0.2` |
| Section | Environment Setup |
| EKS cluster | `my-cluster` |
| Node provisioning | eksctl (this guide) |
| Duration | ~30 min |
| Validation status | `draft` |

## Takeaway

EKS control plane in `us-east-1` spanning two availability zones. **Workload nodepool** `${NODEGROUP_NAME}` (4× `i8g.2xlarge`) is created in step **0.2-nodes** before AKO install. Lab 1.1 re-ensures the same pool after full reset.

## Prerequisites

- Lab 0.1 complete
- EC2 key pair `aerolab-base_us-east-1` in target region
- Quota for 4× `i8g.2xlarge` across `AWS_ZONES` (default: `us-east-1c`, `us-east-1d`)

## Starting state

No EKS cluster, or existing cluster you intend to reuse.

## Steps

1. Source environment:

   ```bash
   source scripts/env/workshop.env
   ```

2. Create cluster (control plane only):

   ```bash
   ./scripts/setup/02-bootstrap-eks.sh
   ```

   **Expected:** eksctl completes; `kubectl get nodes` shows **no** workload nodes yet.

3. Create workload nodepool (step 0.2-nodes):

   ```bash
   ./scripts/setup/02-ensure-workload-nodepool.sh
   ```

   **Expected:** `${NODE_COUNT}`× `${NODE_TYPE}` nodes Ready across `${AWS_ZONES}`.

4. Confirm namespace:

   ```bash
   kubectl get namespace aerospike
   ```

   **Expected:** Namespace `aerospike` exists.

## Verify (pass/fail)

```bash
kubectl get nodes -o wide
```

**Pass:** EKS cluster reachable; `${NODE_COUNT}` workload nodes Ready (`${NODEGROUP_NAME}`).

Reference config: [clusters/main-cluster.yaml](../../clusters/main-cluster.yaml)

## Observe

- Workload nodegroup `${NODEGROUP_NAME}` is created in step **0.2-nodes**; Lab 1.1 re-ensures after full reset via `prepare-lab.sh 1.1`
- Vertical scale to `i8g.4xlarge` happens in Lab 1.3

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Key pair not found | Create in EC2 or update `SSH_PUBLIC_KEY` in workshop.env |
| Insufficient capacity | Request quota increase before Lab 1.1 |

## Teardown / handoff

Cluster remains running. Proceed to AKO install (0.3). Workload nodes: step 0.2-nodes (or `./scripts/setup/setup-all.sh --step 0.2-nodes`).

**Karpenter path:** see [02-eks-cluster-karpenter.md](02-eks-cluster-karpenter.md) when `NODE_PROVISIONING=karpenter`.

## References

- [`scripts/setup/02-bootstrap-eks.sh`](../../scripts/setup/02-bootstrap-eks.sh)
- [Amazon EKS getting started](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)
