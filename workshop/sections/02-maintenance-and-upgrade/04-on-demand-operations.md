# Lab 2.4 — On-Demand Operations

| Field | Value |
|-------|-------|
| Lab ID | `2.4` |
| Section | Maintenance & Upgrade |
| EKS cluster | `my-cluster` |
| AKO min version | `4.4.0` |
| Aerospike baseline | dim 3-node |
| Deploy path | both |
| Duration | ~10 min |
| Validation status | `draft` |
| Official docs | [On-demand operations](https://aerospike.com/docs/kubernetes/manage/configure/on-demand-operations) |

## Takeaway

`spec.operations` triggers targeted actions like **PodRestart** without a full cluster rolling upgrade.

## Prerequisites

- dim cluster Running
- Reference: [manifests/pod-restart-op.yaml](../../manifests/pod-restart-op.yaml)

## Steps

### Path A — kubectl

1. Deploy baseline if needed, then apply operation:

   ```bash
   kubectl apply -f manifests/pod-restart-op.yaml
   ```

2. Watch operator execute PodRestart:

   ```bash
   kubectl -n aerospike get pods -w
   kubectl -n aerospike describe aerospikecluster aerocluster | grep -A10 Operations
   ```

   **Expected:** Targeted pod restart; operation status updated in CR.

### Path B — Helm

Upgrade with `helm/pod-restart-op-values.yaml` containing:

```yaml
operations:
  - kind: PodRestart
    id: pod-restart-1
```

## Verify (pass/fail)

**Pass:** Operation completes; cluster phase returns `Completed`; restarted pod has recent start time.

```bash
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}'
```

## Observe

- Difference from image upgrade (2.3) — operation is explicit one-shot in CR
- Operator logs show operation reconciliation

## Handoff

Proceed to [Lab 2.5](05-k8s-node-maintenance.md).

## References

- [manifests/pod-restart-op.yaml](../../manifests/pod-restart-op.yaml)
