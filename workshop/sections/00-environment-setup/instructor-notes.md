# Section 0 — Instructor Notes

## Timing

| Phase | Live demo | Pre-staged |
|-------|-----------|------------|
| Full Section 0 | ~1–1.5 h | 0 min (show 08-validate-environment only) |

## Path selection

- Default **Path A (OLM)** for automated workshop bootstrap
- Offer Path B if audience is Helm-native — decide before class, do not switch mid-session
- Default **NODE_PROVISIONING=eksctl**; offer Karpenter only if audience uses it in production

## Karpenter-specific

| Rule | Why |
|------|-----|
| Do not mix `NODE_PROVISIONING` mid-session | Node labels, NVMe init, and Lab 2.5 content differ |
| Set `KARPENTER_CONSOLIDATION=Off` during demos | Avoid surprise node termination |
| Never demo `k8sNodeBlockList` on Karpenter | AKO #305 — use drain path only |
| Pre-stage 4+ nodes before class | Ensure `NODE_COUNT=4` and per-AZ baseline pools from step 0.2-nodes |
| System MNG uses `CriticalAddonsOnly` taint | EKS-standard pattern — coredns/metrics-server tolerations declared in cluster yaml, not patched ad hoc |
| Partial NodePool apply → reset before bootstrap | Run `01-reset-workload-nodepools.sh` then `02-ensure-workload-nodepool.sh` if zone mismatch or consolidationPolicy errors |

## Karpenter cleanup (`cleanup-lab.sh`)

| Symptom | Fix |
|---------|-----|
| Stuck at "Draining Karpenter workload pools..." | Normal drain can take up to ~15 min; progress is logged every 15s. Manual: `01-reset-workload-nodepools.sh` then `cleanup-lab.sh --main-only --yes` |
| i8g nodes remain after cleanup | Orphan EC2 sweep runs pre/post delete; manual: terminate instances tagged `karpenter.sh/discovery=${CLUSTER_NAME}` |
| Only 2× t3.large nodes remain during delete | Expected — system MNG; removed by `eksctl delete cluster` |

## Pitfalls

| Issue | Mitigation |
|-------|------------|
| EBS CSI IAM fails | Run 05-setup-ebs-storage.sh steps manually; verify OIDC |
| Local disk init skipped | Re-run `06-setup-local-storage.sh`; check nvme-bootstrap init logs |
| Karpenter nodes missing NVMe | Verify nvme-bootstrap DaemonSet after 0.5 |
| CSV stuck Pending | Approve InstallPlan |
| features.conf missing | 01-validate-client.sh catches this early |

## Skip paths

- Pre-stage entire Section 0; start training at Section 1 Lab 1.1
- Skip local storage (0.5 Part B) if only running Lab 1.1 dim — **required for rack labs (1.2–1.3)**

## Discussion prompts

- Why install AKO at 4.2.0 instead of latest? (Upgrade ladder Lab 2.2: 4.3.0 → 4.4.1 → 4.5.0)
- OLM vs Helm tradeoffs — see path-selection-guide.md

## Dual cluster

Step **0.7** creates the upgrade-lab cluster (`my-cluster-k8s-upgrade`) by default for Lab 2.6. It adds ~3× `i8g.2xlarge` cost during Sections 1–2.

- **Parallel bootstrap:** default `setup-all.sh` creates main + upgrade-lab EKS in parallel after 0.1 (~15–25 min saved). Use `--sequential` for sequential EKS bootstrap.
- Skip with `./scripts/setup/setup-all.sh --skip-upgrade-lab` and run `./scripts/labs/prepare-lab.sh 2.6` before that lab
- **Parallel teardown:** default `cleanup-lab.sh` deletes both clusters concurrently (~10–20 min saved). Use `--sequential` for serial delete.
- Scripts restore kubectl to `my-cluster` after step 0.7; use `./scripts/lib/kubecontext.sh show` to verify
