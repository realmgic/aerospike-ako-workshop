# Section 2 — Instructor Notes

## Timing

| Lab | Duration | Notes |
|-----|----------|-------|
| 2.1 | ~15m (+10m optional) | Install verify, collectinfo tarball; optional: global flags, auth |
| 2.2 | ~30–40m | Three steps: 4.3.0 → 4.4.1 → 4.5.0; demo one step live |
| 2.3 | ~20m | Rolling DB upgrade 8.1.0.x → 8.1.2.x (requires AKO 4.5.0) |
| 2.4 | ~10m | WarmRestart then PodRestart (cold) on 8.1.2.x cluster |
| 2.5 | ~25m (+15m add-on) | Two-terminal drain demo: pre-load data; show pod held during `InProgress` + `eviction-blocked`; Karpenter add-on: do-not-disrupt graduation + terminationGracePeriod |
| 2.6 | ~45m | Mostly waiting; pre-stage cluster + Aerospike |

## AKO upgrade (2.2)

- **Never skip versions** in production — enforce ladder in `versions.env`
- Keep cluster Running throughout — key demo point
- DB stays at **8.1.0.x** during AKO upgrade (AKO 4.2.0–4.4.1 max); 8.1.2.x comes in Lab 2.3 after 4.5.0
- Per-step timing ~15–20 min (OLM wait)

## Lab 2.6 (control plane)

- **Separate cluster only** — `./scripts/lib/kubecontext.sh upgrade-lab` or `./scripts/labs/prepare-lab.sh 2.6`
- Start demo with Aerospike already Running + optional load
- Do not tear down Aerospike during upgrade
- After Lab 2.6 (keep main cluster): `./scripts/cleanup-lab.sh --upgrade-lab-only --yes` then `./scripts/lib/kubecontext.sh main`
- End of full training: `./scripts/cleanup-lab.sh --yes` (both clusters)

## Lab 2.5 (node maintenance)

- **Pre-load data** — empty cluster migrates too fast (especially `--dim`); run `load-data.sh` or `prepare-lab.sh 2.5 --load-data`
- **Two-terminal demo** — Terminal A: `kubectl drain`; Terminal B: prove pod still `Running` on node while CR is `InProgress`
- If migration window is too short, increase `MIGRATION_LOAD_RECORDS` (e.g. `8000000`)
- **eksctl path:** drain (primary) + optional blocklist demo
- **Karpenter path:** drain only; optional NodeClaim disruption observe — see [05-k8s-node-maintenance-karpenter.md](05-k8s-node-maintenance-karpenter.md)
- **Never** demo blocklist on Karpenter ([AKO #305](https://github.com/aerospike/aerospike-kubernetes-operator/issues/305))
- **Karpenter add-on (~15m):** run after drain demo when audience is planning to allow voluntary Karpenter disruption
  - Frame customer's `do-not-disrupt` approach as valid Phase 1, not the long-term target
  - Walk the three layers: `do-not-disrupt` → safe eviction → `terminationGracePeriod`
  - Show live NodePool grace value: `kubectl get nodepool … -o jsonpath='{.spec.template.spec.terminationGracePeriod}'`
  - Emphasize AKO docs: Karpenter **force-deletes** after grace period — 600s workshop default is a starting point, not production gospel
  - Do **not** live-demo removing `do-not-disrupt` or enabling consolidation during class unless on a throwaway cluster

- **`CLUSTER_STORAGE_DIM_LABS=2.5`** — disk default everywhere except Lab 2.5 stays in-memory for faster drain demos

## Pitfalls

| Issue | Mitigation |
|-------|------------|
| Section 1 cluster blocks deploy | Run `./scripts/labs/prepare-lab.sh 2.1` — tears down `aerocluster` and deploys baseline (device default) |
| Lab 1.4 / prior 2.3 wrong starting state | Run `./scripts/labs/prepare-lab.sh 2.3` — resets to **8.1.0.x** baseline before DB upgrade |
| CRD delete during Helm upgrade | Never delete CRDs — use replace |
| Force drain | Never demo `--force` |
| Wrong cluster context | `./scripts/lib/kubecontext.sh show`; main labs use `./scripts/labs/prepare-lab.sh <lab>` |
| Wrong cluster after 2.6 / Section 0.7 | `./scripts/lib/kubecontext.sh main` |
| EKS version unsupported | Adjust START/TARGET to (latest-1)→latest |
| DB 8.1.2.x before AKO 4.5.0 | Baseline manifests use 8.1.0.x; upgrade only in Lab 2.3 |

## Curriculum order

Emphasize: **2.2 → 1.4 → 2.3–2.6**

## Skip paths

- Pre-stage AKO at 4.5.0; demo one upgrade step only
- Defer 2.6 if no budget for second cluster
