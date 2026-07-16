# Lab 0.3 — Install AKO (Path A: OLM)

| Field | Value |
|-------|-------|
| Lab ID | `0.3` |
| Section | Environment Setup |
| EKS cluster | `my-cluster` |
| AKO version | `4.2.0` (intentionally older for Lab 2.2) |
| Deploy path | A (kubectl/OLM) |
| Duration | ~20 min |
| Validation status | `draft` |

## Takeaway

AKO is installed via OLM at version **4.2.0**, watching the `aerospike` namespace.

## Prerequisites

- Lab 0.2 and step **0.2-nodes** complete (schedulable workload nodes available)
- `DEPLOY_PATH=olm` in workshop.env

## Steps

1. Install AKO:

   ```bash
   ./scripts/setup/03-install-ako.sh
   ```

2. Watch CSV until Succeeded:

   ```bash
   kubectl get csv -n operators aerospike-kubernetes-operator.v4.2.0 -w
   ```

   **Expected:** PHASE `Succeeded` (Ctrl+C to exit watch).

3. Verify operator pod:

   ```bash
   kubectl -n operators get pods
   kubectl -n operators logs deployment/aerospike-operator-controller-manager --tail=20
   ```

   **Expected:** Controller manager pod `Running`; logs show webhook registration.

## Verify (pass/fail)

```bash
kubectl get csv -n operators | grep aerospike-kubernetes-operator.v4.2.0
```

**Pass:** CSV exists with phase `Succeeded`.

## Observe

- OLM creates Subscription and InstallPlan in `operators` namespace
- Operator version pinned to 4.2.0 for upgrade ladder in Lab 2.2 (4.3.0 → 4.4.1 → 4.5.0)

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| CSV NotFound / wrong version | OperatorHub stable head may be newer than 4.2.0. Script pins `startingCSV`; if you ran the old install YAML first, delete subscriptions: `kubectl delete subscription -n operators my-aerospike-kubernetes-operator aerospike-kubernetes-operator --ignore-not-found` then re-run `./scripts/setup/03-install-ako.sh` |
| CSV Pending | Check InstallPlan: `kubectl get installplan -n operators`; approve if Manual: `kubectl patch installplan <name> -n operators --type merge -p '{"spec":{"approved":true}}'` |
| Operator pod CrashLoop | Check logs; verify cluster has sufficient resources |

## Not covered here

Helm install → [03-install-ako-helm.md](03-install-ako-helm.md)

## Teardown / handoff

Proceed to [Lab 0.4 — akoctl](04-install-akoctl.md).

## References

- [Install AKO via OLM](https://aerospike.com/docs/kubernetes/install/olm/)
