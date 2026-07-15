# Section 1 — Scaling & Capacity

## Section takeaway

AKO scales Aerospike clusters horizontally, vertically, across racks, and adjusts replication — each operation has distinct CR fields and observable behavior.

## Lab tracks

| Track | Profile | Labs |
|-------|---------|------|
| **A** | In-memory dim cluster | 1.1, 1.2 |
| **B** | 2-rack block storage + vertical scale | 1.3, 1.4 |
| **A′** | Replication factor (deferred) | 1.5 — **run after [Lab 2.2](../02-maintenance-and-upgrade/02-upgrade-ako.md)** |

## Reset-and-redeploy flow

Default: **full reset** between labs (`reset-cluster.sh` removes database + workload nodes). Exceptions:

| Lab | Reset | Command |
|-----|-------|---------|
| 1.1 | Full | `./scripts/labs/prepare-lab.sh 1.1` |
| 1.2 | Light | `./scripts/labs/prepare-lab.sh 1.2` (keeps nodes; scales 2xl pool 5 → 4) |
| 1.3 | Light | `./scripts/labs/prepare-lab.sh 1.3` (reuses 2xl pool; `--full` for hard wipe) |
| 1.4 | **Light** | `./scripts/labs/prepare-lab.sh 1.4` (light reset; baseline 2xl, then vertical pool in lab) |
| 1.5 | Light | `./scripts/labs/prepare-lab.sh 1.5` (after Lab 2.2; keeps `${NODEGROUP_NAME}` 2xl pool) |

Continuing Track A → B in one session (1.2 → 1.3): light reset only — no nodepool delete/recreate.

Switching tracks after a break or from a broken state: run `prepare-lab.sh <lab> --full` before the first lab of the new track.

## Labs

| Lab | Title | Duration | Run order |
|-----|-------|----------|-----------|
| 1.1 | [Horizontal scaling](01-horizontal-scaling.md) | ~15m | — |
| 1.2 | [Rack awareness](02-rack-awareness-basics.md) | ~20m | After 1.1 |
| 1.3 | [Vertical scaling & rack revision](03-rack-revision.md) | ~45m | After 1.2 (Track B) |
| 1.4 | [Rack replacement](04-rack-replacement.md) | ~30m | Standalone (Track B) |
| 1.5 | [Replication factor](05-replication-factor.md) | ~15m | **After [Lab 2.2](../02-maintenance-and-upgrade/02-upgrade-ako.md)** |

**Note:** Lab 1.5 is listed in Section 1 but requires AKO **4.4.0+** — do not run until [Lab 2.2](../02-maintenance-and-upgrade/02-upgrade-ako.md) completes the 4.4.1 upgrade step.

## Karpenter observe (optional)

When `NODE_PROVISIONING=karpenter`, watch node provisioning during scale-up labs:

```bash
kubectl get nodeclaims,nodes -w
```

Labs 1.1, 1.3 (vertical scale), and 1.4 are the best demos for Karpenter provisioning new i8g nodes.

## Instructor notes

See [instructor-notes.md](instructor-notes.md).
