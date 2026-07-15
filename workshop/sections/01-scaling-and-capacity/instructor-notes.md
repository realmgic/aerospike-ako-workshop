# Section 1 — Instructor Notes

## Timing

| Lab | Duration | Notes |
|-----|----------|-------|
| 1.1 | ~15m | Quick win — scale up/down |
| 1.2 | ~20m | Pod naming change is key observable |
| 1.3 | ~45m | Longest — node resize + migration wait; use minimal data |
| 1.4 | ~30m | Discuss revision vs replacement |
| 1.5 | ~15m | **After Lab 2.2** — dynamic RF demo; reuses dim on `${NODEGROUP_NAME}` (light reset) |

## Tracks

- **Track A** (dim): 1.1 → 1.2 → (optional) 1.3 → 1.4
- **Track B** (rack + vertical scale): 1.3 → 1.4 (or continue from 1.2 on same 2xl pool)
- Use `prepare-lab.sh` for reset + nodes; `--full` only when a hard wipe is needed

## Reset shortcuts

| Session | Approach |
|---------|----------|
| Full day Track A→B | 1.1 (full) → 1.2 (light, scale 5→4) → 1.3 (light, reuse 2xl) → 1.4 (light, standalone) |
| Half-day Track A | Pre-run `prepare-lab.sh 1.1`; light reset for 1.2 only |
| Track B only | `prepare-lab.sh 1.3` or `1.4` independently (both light reset + 2xl baseline) |
| Broken / cold start | `prepare-lab.sh <lab> --full` |

Full reset adds ~5–15 min (node provisioning + nvme-bootstrap on first 2xl create). Reusing pools between 1.1–1.3 avoids that cost — nvme-bootstrap runs once per new i8g node, not on every `prepare-lab.sh`.

## Pitfalls

| Issue | Mitigation |
|-------|------------|
| Scale-up pods Pending on eksctl | Run `lab-nodes.sh 1.1 ensure --scale-up` before scale-up manifest |
| 1.2 starts with 5 nodes from 1.1 | `prepare-lab.sh 1.2` scales 2xl pool back to 4 automatically |
| Rack pods Pending (node affinity) | `prepare-lab.sh 1.2` validates multi-AZ; `--full` if skewed |
| Scale-down stuck | migrate-fill-delay; wait or reduce data |
| Lab 1.3 Phase 2 quota | Expect **8 nodes** (4×2xl idle + 4×4xl); verify EC2 quota |
| Lab 1.4 standalone | Light reset at start; redeploys v1 then vertical pool — **does not require 1.3 v2** |
| Missing node-pool labels | Re-run `lab-nodes.sh <lab> ensure`; eksctl path patches labels after scale |
| Lab 1.5 before AKO 4.4.0 | Follow curriculum: 2.2 first |
| Lab 1.5 full reset unnecessary | Default is light reset; use `--skip-reset` if dim from 2.2 still Running |
| Batch scale-down on SC | Call out AP-only constraint |

## Skip paths

- Track A only for half-day session
- Defer Track B to advanced session
- Skip 1.5 if AKO upgrade not demoed

## Discussion prompts

- Vertical scale + revision (1.3) — node pool locator + revision + dual local-ssd
- Revision (1.3) vs replacement (1.4) — both reach 2× vertical profile; revision keeps rack IDs, replacement changes them (3+4)
- RF change without restart (1.5) — AP vs SC limitations
