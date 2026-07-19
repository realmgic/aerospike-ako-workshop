# Archived workshop artifacts

Superseded or unused files kept for reference. Active labs should use the replacements listed below.

## Deploy scripts (superseded by `cluster-storage.sh`)

| Archived file | Use instead |
|---------------|-------------|
| `scripts/labs/deploy-disk-cluster.sh` | `./scripts/labs/deploy-cluster.sh` (default `CLUSTER_STORAGE=disk`) |
| `scripts/labs/deploy-disk-cluster-helm.sh` | `./scripts/labs/deploy-cluster-helm.sh` |
| `scripts/labs/deploy-disk-cluster-maintenance.sh` | `./scripts/labs/deploy-cluster-maintenance.sh` |
| `scripts/labs/deploy-disk-cluster-maintenance-helm.sh` | `./scripts/labs/deploy-cluster-maintenance-helm.sh` |
| `scripts/labs/deploy-dim-cluster-maintenance.sh` | `./scripts/labs/prepare-lab.sh 2.5 --dim` then `./scripts/labs/deploy-cluster-maintenance.sh` |
| `scripts/labs/deploy-dim-cluster-maintenance-helm.sh` | `./scripts/labs/prepare-lab.sh 2.5 --dim` then `./scripts/labs/deploy-cluster-maintenance-helm.sh` |

## Load-data wrappers

| Archived file | Use instead |
|---------------|-------------|
| `scripts/labs/load-migration-data.sh` | `./scripts/labs/load-data.sh` |
| `scripts/labs/load-dim-migration-data.sh` | `./scripts/labs/load-data.sh` |

## Optional Lab 1.1 scale-down batch (never wired into guide)

| Archived file | Notes |
|---------------|-------|
| `manifests/scale-down-batch.yaml` | Lab 1.1 scale-down uses re-applying baseline manifest |
| `helm/scale-down-batch-values.yaml` | Paired values for above |

## Lab 1.4 replication-factor (naming cleanup)

| Archived file | Use instead |
|---------------|-------------|
| `manifests/replication-factor-rf3.yaml` | `manifests/disk-replication-factor-rf3.yaml` or `manifests/dim-replication-factor-rf3.yaml` |
| `helm/replication-factor-rf3-values.yaml` | `helm/disk-replication-factor-rf3-values.yaml` or `helm/dim-replication-factor-rf3-values.yaml` |

Moved here when dim/disk naming was aligned with the rest of the workshop.
