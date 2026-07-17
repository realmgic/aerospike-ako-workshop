# Lab 2.6 — K8s Control Plane Upgrade

| Field | Value |
|-------|-------|
| Lab ID | `2.6` |
| Section | Maintenance & Upgrade |
| EKS cluster | **`my-cluster-k8s-upgrade` only** |
| K8s upgrade | `1.31 → 1.32` |
| Aerospike baseline | 3-node in-memory **Running before upgrade** |
| Duration | ~45 min (mostly waiting) |
| Validation status | `draft` |
| Official docs | [EKS cluster upgrade](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html) |

## Takeaway

A live Aerospike cluster keeps running during EKS control plane upgrade — you must still upgrade the node group afterward to align kubelet versions.

## Prerequisites

- Upgrade-lab cluster created during Section 0 step **0.7**, or pre-staged before this lab (see **Phase 0 — Prepare lab** below)
- Optional: light load via asbench left running

## Phase 0 — Prepare lab

```bash
./scripts/labs/prepare-lab.sh 2.6
```

Or switch context manually:

```bash
./scripts/lib/kubecontext.sh upgrade-lab
```

**Expected:** Upgrade-lab cluster exists; 3 Aerospike pods Running before starting demo.

## Starting state

```bash
./scripts/lib/kubecontext.sh show
./scripts/labs/prepare-lab.sh 2.6 --skip-reset   # validate only if already staged
kubectl -n aerospike get pods -l aerospike.com/cr=aerocluster
aws eks describe-cluster --name my-cluster-k8s-upgrade --query cluster.version
```

**Pass:** 3/3 Running; version `1.31`.

## Steps

| Step | Action |
|------|--------|
| 0 | Confirm Aerospike live (3/3 Running) |
| 1 | Record starting K8s version |
| 2 | Pre-upgrade checks (deprecated APIs, addons) |
| 3 | **Upgrade control plane** — do NOT scale down Aerospike |

```bash
./scripts/setup/upgrade-lab/upgrade-control-plane.sh
```

| 4 | Watch Aerospike in parallel terminal |

```bash
watch kubectl -n aerospike get pods
```

**Expected:** Pods stay Running (brief kubectl API delays possible).

| 5 | Wait for cluster ACTIVE (~10–20 min) |
| 6 | Upgrade node group |

```bash
./scripts/setup/upgrade-lab/upgrade-nodegroup.sh
```

| 7 | Post-upgrade validation |

```bash
./scripts/setup/upgrade-lab/validate-post-upgrade.sh
```

## Verify (pass/fail)

- EKS cluster version `1.32`
- 3 Aerospike pods `Running`
- CR phase `Completed`
- `asadm` shows `cluster_size` 3

## Observe

- EKS console upgrade progress
- No unplanned Aerospike restarts until nodegroup upgrade (step 6)

## Not covered here

- Worker drain → [Lab 2.5](05-k8s-node-maintenance.md)
- AKO upgrade → [Lab 2.2](02-upgrade-ako.md)

## Teardown

After Lab 2.6 demo, if continuing with main-cluster labs:

```bash
./scripts/cleanup-lab.sh --upgrade-lab-only --yes
./scripts/lib/kubecontext.sh main
```

End of full training (delete **both** clusters in parallel):

```bash
./scripts/cleanup-lab.sh --yes
```

Use `--sequential` to delete one cluster at a time (sequential order).

## References

- [eksctl cluster upgrade](https://docs.aws.amazon.com/eks/latest/eksctl/cluster-upgrade.html)
