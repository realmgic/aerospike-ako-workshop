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

EKS control plane in `us-east-1` spanning two availability zones. **Workload nodes are created in Lab 1.1** via `prepare-lab.sh`.

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

3. Confirm namespace:

   ```bash
   kubectl get namespace aerospike
   ```

   **Expected:** Namespace `aerospike` exists.

## Verify (pass/fail)

```bash
kubectl get nodes -o wide
```

**Pass:** EKS cluster reachable; 0 workload nodes (Lab 1.1 creates `${NODEGROUP_NAME}`).

Reference config: [clusters/main-cluster.yaml](../../clusters/main-cluster.yaml)

## Observe

- Workload nodegroup `${NODEGROUP_NAME}` is created in [Lab 1.1](../01-scaling-and-capacity/01-horizontal-scaling.md) via `prepare-lab.sh 1.1`
- Vertical scale to `i8g.4xlarge` happens in Lab 1.3

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Key pair not found | Create in EC2 or update `SSH_PUBLIC_KEY` in workshop.env |
| Insufficient capacity | Request quota increase before Lab 1.1 |

## Teardown / handoff

Cluster remains running. Proceed to AKO install (0.3). Workload nodes: Lab 1.1.

**Karpenter path:** see [02-eks-cluster-karpenter.md](02-eks-cluster-karpenter.md) when `NODE_PROVISIONING=karpenter`.

## References

- [`scripts/setup/02-bootstrap-eks.sh`](../../scripts/setup/02-bootstrap-eks.sh)
- [Amazon EKS getting started](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)
