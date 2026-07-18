# Section 1 — Scaling & Capacity

## Section takeaway

AKO scales Aerospike clusters horizontally, vertically, across racks, and adjusts replication — each operation has distinct CR fields and observable behavior.

## Lab tracks

| Track | Profile | Labs |
|-------|---------|------|
| **A** | Device storage cluster (default; `--dim` for in-memory) | 1.1, 1.2 |
| **B** | 2-rack block storage + vertical scale | 1.3, 1.4 |
| **A′** | Replication factor (deferred) | 1.5 — **run after [Lab 2.2](../02-maintenance-and-upgrade/02-upgrade-ako.md)** |

## Reset-and-redeploy flow

Default: **light reset** between Section 1 labs (1.2–1.5). Lab **1.1** runs a **full reset** (same as default `prepare-lab.sh 1.1`). Use **full reset** only for cold start or recovery.

| Lab | Reset | Command |
|-----|-------|---------|
| 1.1 | Full | `./scripts/labs/prepare-lab.sh 1.1` |
| 1.2 | Light | `./scripts/labs/prepare-lab.sh 1.2` (keeps nodes; scales baseline pool 5 → 4) |
| 1.3 | Light | `./scripts/labs/prepare-lab.sh 1.3` (reuses baseline pool; `--full` for hard wipe) |
| 1.4 | **Light** | `./scripts/labs/prepare-lab.sh 1.4` (light reset; baseline pool, then vertical pool in lab) |
| 1.5 | Light | `./scripts/labs/prepare-lab.sh 1.5` (after Lab 2.2; keeps baseline pool) |

Continuing Track A → B in one session (1.2 → 1.3): light reset only — no nodepool delete/recreate.

**Recovery** (cold start or broken state):

```bash
./scripts/reset-cluster.sh --yes
./scripts/labs/prepare-lab.sh <lab-id>
```

`prepare-lab.sh <lab> --full` is shorthand for full reset + ensure.

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
kubectl get nodes -l workshop.aerospike.com/node-pool=baseline -w
```

Labs 1.1, 1.3 (vertical scale), and 1.4 are the best demos for Karpenter provisioning new i8g nodes.

## Instructor notes

See [instructor-notes.md](instructor-notes.md).
