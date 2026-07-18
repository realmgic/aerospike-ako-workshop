# Section 1 — Instructor Notes

## Timing

| Lab | Duration | Notes |
|-----|----------|-------|
| 1.1 | ~15m | Quick win — scale up/down |
| 1.2 | ~60m | Longest in Section 1 — rack awareness + vertical scale + revision; use minimal data |
| 1.3 | ~30m | Discuss revision vs replacement |
| 1.4 | ~15m | **After Lab 2.2** — dynamic RF demo; reuses baseline pool cluster (light reset) |

## Cluster storage

- **Default:** device storage on local-ssd (`CLUSTER_STORAGE=disk` in workshop.env)
- **In-memory:** `./scripts/labs/prepare-lab.sh <lab> --dim`, `CLUSTER_STORAGE=dim`, or per-lab `CLUSTER_STORAGE_DIM_LABS` — applies to **Lab 1.1** and Section 2; rack labs (1.2–1.3) always use hybrid block storage
- Lab 1.1 needs baseline local-ssd PVs when using disk (post Lab 0.5)

## Session shortcuts

| Session | Approach |
|---------|----------|
| Full day Section 1 | 1.1 (full) → 1.2 (light, scale 5→4) → 1.3 (light, standalone) |
| Half-day core | Pre-run `prepare-lab.sh 1.1`; light reset for 1.2 only |
| Replacement only | `prepare-lab.sh 1.3` independently (light reset + baseline pool) |
| Broken / cold start | `reset-cluster.sh --yes` then `prepare-lab.sh <lab>` (or `prepare-lab.sh <lab> --full`) |

Full reset adds ~5–15 min (node provisioning + nvme-bootstrap on first i8g create). Reusing pools between 1.1–1.2 avoids that cost — nvme-bootstrap runs once per new i8g node, not on every `prepare-lab.sh`.

## Pitfalls

| Issue | Mitigation |
|-------|------------|
| Scale-up pods Pending on eksctl | Run `lab-nodes.sh 1.1 ensure --scale-up` before scale-up manifest |
| 1.2 starts with 5 nodes from 1.1 | `prepare-lab.sh 1.2` scales baseline pool back to 4 automatically |
| Rack pods Pending (node affinity) | `./scripts/reset-cluster.sh --yes && ./scripts/labs/prepare-lab.sh 1.2` |
| Scale-down stuck | migrate-fill-delay; wait or reduce data |
| Lab 1.2 Phase 2 quota | Expect **8 nodes** (4× baseline idle + 4× vertical); verify EC2 quota |
| Lab 1.3 standalone | Light reset at start; redeploys v1 then vertical pool — **does not require 1.2 v2** |
| Missing node-pool labels | Re-run `lab-nodes.sh <lab> ensure`; eksctl path patches labels after scale |
| Lab 1.4 before AKO 4.4.0 | Follow curriculum: 2.2 first |
| Lab 1.4 full reset unnecessary | Default is light reset; use `--skip-reset` if dim from 2.2 still Running |
| Batch scale-down on SC | Call out AP-only constraint |

## Skip paths

- Section 1 only for half-day session (1.1 + 1.2)
- Skip 1.3 replacement if time-constrained
- Skip 1.4 if AKO upgrade not demoed

## Discussion prompts

- Vertical scale + revision (1.2) — node pool locator + revision + dual local-ssd
- Revision (1.2) vs replacement (1.3) — both reach 2× vertical profile; revision keeps rack IDs, replacement changes them (3+4)
- RF change without restart (1.4) — scale up 2→3, then `./scripts/labs/deploy-cluster.sh` again for immediate 3→2; AP vs SC limitations
