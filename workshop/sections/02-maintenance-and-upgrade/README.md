# Section 2 — Maintenance & Upgrade

## Section takeaway

AKO and the platform can be upgraded and maintained safely — operator upgrades, DB upgrades, node eviction, control plane upgrades, and on-demand operations each have distinct procedures.

## Prerequisites

Section 0 complete. Run `./scripts/labs/prepare-lab.sh 2.1` before Lab 2.1 (cluster baseline after Section 1; device storage default). Run `./scripts/labs/prepare-lab.sh 2.3` before Lab 2.3 if coming from Lab 1.4 or retrying the DB upgrade. Run `./scripts/labs/prepare-lab.sh 2.5` before Lab 2.5 (teardown + fresh maintenance cluster; optional `--load-data`). Default storage is device (`CLUSTER_STORAGE=disk`); use `--dim` for in-memory.

## Labs

| Lab | Title | Cluster | Duration |
|-----|-------|---------|----------|
| 2.1 | [akoctl — install, config, logs](01-akoctl.md) | `my-cluster` | ~25m |
| 2.2 | [Upgrade AKO](02-upgrade-ako.md) | `my-cluster` | ~45–60m |
| — | → then [Lab 1.4](../01-scaling-and-capacity/04-replication-factor.md) (replication factor) | `my-cluster` | ~15m |
| 2.3 | [Upgrade Aerospike DB](03-upgrade-aerospike-db.md) | `my-cluster` | ~20m |
| 2.4 | [On-demand operations](04-on-demand-operations.md) | `my-cluster` | ~10m |
| 2.5 | [K8s node maintenance](05-k8s-node-maintenance.md) ([Karpenter add-on](05-k8s-node-maintenance-karpenter.md#add-on--graduating-from-do-not-disrupt-to-karpenter-native-disruption-15-min)) | `my-cluster` | ~25m (+15m Karpenter add-on) |
| 2.6 | [K8s control plane upgrade](06-k8s-control-plane-upgrade.md) | `my-cluster-k8s-upgrade` | ~45m |

**Curriculum:** Complete **2.2** (through AKO 4.4.1 minimum), then run **[Lab 1.4](../01-scaling-and-capacity/04-replication-factor.md)** before continuing to 2.3–2.6.

## Instructor notes

See [instructor-notes.md](instructor-notes.md).
