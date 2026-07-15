# Lab 2.5 — K8s Worker Node Maintenance (Karpenter)

| Field | Value |
|-------|-------|
| Lab ID | `2.5` |
| Section | Maintenance & Upgrade |
| EKS cluster | `my-cluster` |
| Node provisioning | **Karpenter** |
| AKO min version | `4.4.0` |
| Duration | ~25 min |
| Validation status | `draft` |
| Official docs | [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance) |

## Takeaway

On Karpenter, use **drain + AKO safe eviction** for node maintenance. **`k8sNodeBlockList` is not supported** — Karpenter rejects `kubernetes.io/hostname` node affinity ([AKO #305](https://github.com/aerospike/aerospike-kubernetes-operator/issues/305)).

## Prerequisites

- `NODE_PROVISIONING=karpenter`
- `safePodEviction.enable=true` on operator
- NodePool `terminationGracePeriod` ≥600s (configured in bootstrap)
- Cluster Running; note pod→node mapping

## Steps — Drain path (primary)

Same as eksctl path — AKO safe eviction applies regardless of node provisioner:

1. Find node hosting an Aerospike pod:

   ```bash
   kubectl -n aerospike get pods -o wide
   NODE=<node-name>
   ```

2. Attempt drain:

   ```bash
   kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
   ```

   **Expected:** Eviction blocked or delayed; annotation `aerospike.com/eviction-blocked` may appear.

3. Wait for CR `Completed`, retry drain.

4. **Pass:** Drain succeeds without `--force` after cluster stable.

## Steps — Observe Karpenter disruption (optional demo)

After successful drain, show how Karpenter manages node lifecycle:

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

3. Discuss NodePool disruption settings:

   ```bash
   kubectl get nodepool "${KARPENTER_NODEPOOL_NAME}" -o yaml | grep -A6 disruption
   ```

   **Do not** force-delete nodes — bypasses AKO safe eviction webhook.

## Verify (pass/fail)

**Pass:** Node drained; Aerospike pods `Running` on other nodes; CR `Completed`. No `k8sNodeBlockList` applied.

## What NOT to demo on Karpenter

| Technique | Status |
|-----------|--------|
| `kubectl drain` + safe eviction | **Supported** |
| `k8sNodeBlockList` | **Unsupported** — eksctl path only |
| `kubectl delete node --force` | **Never** — bypasses webhook |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Node not terminating after drain | Check PDB; verify terminationGracePeriod |
| Replacement node missing NVMe | Verify `nvme-bootstrap` DaemonSet Ready |
| Consolidation removes nodes mid-lab | Set `KARPENTER_CONSOLIDATION=Off` |

## References

- [Node maintenance](https://aerospike.com/docs/kubernetes/manage/node-maintenance)
- [AKO #305 — blocklist + Karpenter](https://github.com/aerospike/aerospike-kubernetes-operator/issues/305)
