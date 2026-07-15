# Lab X.Y — Title

| Field | Value |
|-------|-------|
| Lab ID | `X.Y` |
| Section | Section Name |
| EKS cluster | `my-cluster` |
| Aerospike cluster | `aerocluster` |
| AKO min version | `4.2.0` |
| Aerospike baseline | dim 3-node / rack block / none |
| Deploy path | A (kubectl) / B (Helm) / both |
| Duration | ~N min |
| Validation status | `draft` |
| Official docs | [link](https://aerospike.com/docs/kubernetes/) |

## Takeaway

One sentence describing what trainees must remember.

## Prerequisites

- Section 0 phases complete (list which)
- Prior labs (if any)
- AKO / Aerospike version requirements
- Cluster state before starting

## Node requirements (Section 1 labs)

| Item | Value |
|------|-------|
| Instance | e.g. `i8g.2xlarge` × 4 |
| Reset | Full / Light / None — see Section 1 README |
| Nodegroups | 1 × `${NODEGROUP_NAME}` (eksctl) or NodePool `${KARPENTER_NODEPOOL_NAME}` (Karpenter) |

## Phase 0 — Prepare lab (Section 1)

```bash
./scripts/labs/prepare-lab.sh X.Y
```

## Starting state

Describe what must already be running (pods, AKO version, kubeconfig context).

## Deploy baseline (if needed)

```bash
# From workshop/ directory
./scripts/labs/deploy-dim-cluster.sh
```

**Expected:** 3 pods Running; `AerospikeCluster` phase `Completed`.

## Background

3–5 sentences explaining what AKO does for this operation and why it matters.

## Steps

### Path A — kubectl

1. Run the command:

   ```bash
   kubectl apply -f manifests/example.yaml
   ```

   **Expected:** `aerospikecluster.asdb.aerospike.com/aerocluster configured`

2. Watch reconciliation:

   ```bash
   kubectl -n aerospike get pods -w
   ```

   **Expected:** Pods reach `Running`; CR status `Completed`.

### Path B — Helm

1. Run the command:

   ```bash
   helm upgrade --install aerocluster aerospike/aerospike-cluster \
     --namespace aerospike \
     --version "${AKO_VERSION_START}" \
     -f helm/example-values.yaml
   ```

   **Expected:** Release status `deployed`.

## Verify (pass/fail)

1. Pod count matches `spec.size`:

   ```bash
   kubectl -n aerospike get pods -l aerospike.com/cr=aerocluster --no-headers | wc -l
   ```

   **Pass:** Count equals expected size.

2. Cluster phase is Completed:

   ```bash
   kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}'
   ```

   **Pass:** Output is `Completed`.

3. Run shared verification:

   ```bash
   ./scripts/verify-cluster.sh
   ```

## Observe

- CR status fields relevant to this lab
- Pod naming pattern changes (if applicable)

Watch AKO reconcile during the operation:

```bash
kubectl -n operators logs -f deployment/aerospike-operator-controller-manager manager
```

For a log snapshot use `--tail=100` without `-f`, or run `./scripts/verify-cluster.sh`.

## Troubleshooting

For AKO logs and general diagnostics, see [Troubleshooting](../README.md#troubleshooting) in the workshop README.

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| CR stuck in InProgress | Resource constraints or storage | `kubectl -n aerospike describe aerospikecluster aerocluster`; AKO logs: `kubectl -n operators logs -f deployment/aerospike-operator-controller-manager manager`; `./scripts/verify-cluster.sh` |
| Pods Pending | Insufficient nodes or PVC binding | `kubectl -n aerospike describe pod <name>`; check node pool labels and PVC/PV state (see README) |
| Reconcile errors in operator logs | Controller or webhook failure | Follow AKO logs (`-f … manager`); `./scripts/verify-cluster.sh` |

## Teardown / handoff

State what to leave running for the next lab, or run:

```bash
./scripts/labs/prepare-lab.sh <next-lab>   # recommended (handles reset + nodes)
./scripts/reset-cluster.sh --yes           # if done for the day
```

## Not covered here

- Related topic → [Lab X.Y](link)

## References

- [Official doc](https://aerospike.com/docs/kubernetes/)
