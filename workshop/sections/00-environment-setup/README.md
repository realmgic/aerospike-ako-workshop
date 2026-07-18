# Section 0 — Environment Setup

## Section takeaway

You can stand up a complete EKS lab platform — cluster, AKO, storage layers, and secrets — that all downstream labs reuse without re-explaining infrastructure.

## Setup steps

| Step | Guide | Duration |
|------|-------|----------|
| 0.1 | [Prerequisites](01-prerequisites.md) | ~15m |
| 0.2 | EKS cluster — [eksctl MNG](02-eks-cluster.md) or [Karpenter](02-eks-cluster-karpenter.md) | ~15–25m (parallel with 0.7 bootstrap) |
| 0.2-nodes | Baseline per-AZ workload pools | ~10–15m |
| 0.3 | Install AKO — [OLM](03-install-ako-olm.md) or [Helm](03-install-ako-helm.md) | ~20m |
| 0.4 | [akoctl](04-install-akoctl.md) | ~10m |
| 0.5 | [Storage layer](05-storage-layer.md) | ~25m |
| 0.6 | [Secrets and validation](06-secrets-and-validation.md) | ~10m |
| 0.7 | Upgrade-lab cluster (Lab 2.6) | ~15–25m post-bootstrap (EKS bootstrap runs in parallel with 0.2) |

## Parallel EKS bootstrap (default)

Full `./scripts/setup/setup-all.sh` creates **main** and **upgrade-lab** EKS clusters **in parallel** after step 0.1, using isolated kubeconfig files under `workshop/.kube/` (merged into your default kubeconfig when both finish). This saves roughly **15–25 minutes** vs sequential bootstrap.

- Disable with `./scripts/setup/setup-all.sh --sequential` (sequential EKS bootstrap: 0.2, 0.2-nodes, then 0.3–0.6, then full 0.7)
- Individual `--step` runs are unchanged (no parallel)

| Choose Path A (OLM) when… | Choose Path B (Helm) when… |
|---------------------------|------------------------------|
| Teaching OperatorHub/OLM lifecycle | Audience uses Helm for all K8s deploys |
| Automated bootstrap via [`setup-all.sh`](../../scripts/setup/setup-all.sh) | Teaching values-driven / GitOps workflows |
| OpenShift/OLM-centric environments | Need `helm upgrade` rollback and diff |

See [instructor/path-selection-guide.md](../../instructor/path-selection-guide.md).

## Node provisioning selection

| Choose eksctl MNG when… | Choose Karpenter when… |
|-------------------------|-------------------------|
| Teaching classic EKS nodegroups | Audience uses Karpenter in production |
| Demoing `k8sNodeBlockList` (Lab 2.5) | Teaching dynamic node provisioning |
| Simplest bootstrap | Full main curriculum on autoscaled i8g |

Set `NODE_PROVISIONING=eksctl` or `karpenter` in [workshop.env.example](../../scripts/env/workshop.env.example). Lab 2.6 upgrade-lab cluster always uses eksctl MNG.

## What Section 0 does NOT do

- Does **not** deploy an Aerospike cluster on the main cluster — labs deploy their own baseline
- Does **not** cover scaling, upgrades, or maintenance — Sections 1 and 2

Step **0.7** creates the separate upgrade-lab EKS cluster for Lab 2.6 only (provisions local-ssd when `CLUSTER_STORAGE=disk`, the default). Skip it with `./scripts/setup/setup-all.sh --skip-upgrade-lab` to save cost, then run `./scripts/labs/prepare-lab.sh 2.6` before that lab.

## Step-by-step setup (teaching flow)

Run each setup step individually — script numbers match step IDs:

```bash
cd workshop
cp scripts/env/workshop.env.example scripts/env/workshop.env
source scripts/env/workshop.env

./scripts/setup/setup-all.sh --step 0.1
./scripts/setup/setup-all.sh --step 0.2
./scripts/setup/setup-all.sh --step 0.2-nodes
./scripts/setup/setup-all.sh --step 0.3
./scripts/setup/setup-all.sh --step 0.4
./scripts/setup/setup-all.sh --step 0.5    # ebs + local
./scripts/setup/setup-all.sh --step 0.6    # secrets + validate
./scripts/setup/setup-all.sh --step 0.7    # upgrade-lab (Lab 2.6)
```

Or invoke scripts directly:

```bash
./scripts/setup/01-validate-client.sh
./scripts/setup/02-bootstrap-eks.sh
./scripts/setup/02-ensure-workload-nodepool.sh
./scripts/setup/03-install-ako.sh
./scripts/setup/04-install-akoctl.sh
./scripts/setup/05-setup-ebs-storage.sh
./scripts/setup/06-setup-local-storage.sh
./scripts/setup/07-deploy-secrets.sh
./scripts/setup/08-validate-environment.sh
./scripts/setup/upgrade-lab/setup-upgrade-lab.sh
```

See `./scripts/setup/setup-all.sh --list` for the full step → script mapping.

## Quick orchestration (pre-staging shortcut)

Run all Section 0 steps in one command:

```bash
cd workshop
cp scripts/env/workshop.env.example scripts/env/workshop.env
# Edit DEPLOY_PATH, NODE_PROVISIONING, and paths

./scripts/setup/setup-all.sh
```

Skip the upgrade-lab cluster (defer to Lab 2.6):

```bash
./scripts/setup/setup-all.sh --skip-upgrade-lab
```

## Instructor notes

See [instructor-notes.md](instructor-notes.md).
