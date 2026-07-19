# Instructor Guide: Client Prerequisites

This document applies to the **machine running the training** (instructor laptop or bastion) — not EKS nodes or trainee machines.

## Who needs what

| Role | Client tools |
|------|--------------|
| **Instructor** | Full tool set below |
| **Trainee** (observe-only) | None; optional kubectl for hands-on |
| **Pre-stager** | Same as instructor |

## Tool matrix

| Tool | Path A | Path B | Min version | Verify |
|------|:------:|:------:|-------------|--------|
| AWS CLI | required | required | 2.x | `aws sts get-caller-identity` |
| kubectl | required | required | 1.28+ | `kubectl version --client` |
| eksctl | required | required | 0.190+ | `eksctl version` |
| git | required | required | 2.x | `git --version` |
| bash | required | required | 4.x | — |
| curl | required | required | — | `curl --version` |
| Helm | — | required | 3.12+ | `helm version` |
| Helm (Karpenter) | — | if `NODE_PROVISIONING=karpenter` | 3.12+ | `helm version` |
| krew | required | required | 0.4+ | `kubectl krew version` |
| akoctl | optional | optional | latest | Installed in Lab 0.4; `kubectl krew list \| grep akoctl` |
| jq | recommended | recommended | 1.6+ | `jq --version` |
| OpenSSH | required | required | — | `ssh -V` |

## AWS prerequisites

| Requirement | Verify |
|-------------|--------|
| AWS credentials configured | `aws sts get-caller-identity` |
| IAM for EKS, EC2, IAM, CloudFormation | Create cluster successfully |
| EC2 key pair in region | `aws ec2 describe-key-pairs --region us-east-1` |
| Quota: 4× i8g.2xlarge (main eksctl baseline) | Service Quotas console |
| Quota: 4× i8g.4xlarge (Lab 1.2 vertical scale overlap) | Service Quotas console |
| Quota: 4–8× i8g.2xlarge (main Karpenter min/max) | Service Quotas console |
| Quota: 4–8× i8g.4xlarge (Lab 1.2 Karpenter vertical scale) | Service Quotas console |
| Quota: 3× i8g.2xlarge (upgrade-lab) | Service Quotas console |
| EC2 AZ capacity: `i8g.2xlarge` + `i8g.4xlarge` in each `AWS_ZONES` entry | `./scripts/setup/01b-check-ec2-capacity.sh` (also runs from `01-validate-client.sh`) |
| Karpenter IAM (controller + node roles) | Created by `scripts/setup/karpenter/00-install-controller.sh` |
| feature-key file (`features.conf`) | File at `secrets/features.conf` |
| kubeconfig for both clusters (Lab 2.6) | `./scripts/lib/kubecontext.sh show` |

## Repo layout on client

```text
aerospike-ako-workshop/
└── workshop/
    ├── scripts/env/workshop.env          # local copy from workshop.env.example
    ├── secrets/features.conf             # NOT in git — instructor-supplied license
    ├── vendor/storage/                   # vendored storage manifests
    └── .kube/                            # isolated kubeconfigs (gitignored)
```

## Pre-class runbook

**Step-by-step** (recommended when validating each lab):

```bash
cd workshop
cp scripts/env/workshop.env.example scripts/env/workshop.env
source scripts/env/workshop.env

./scripts/setup/setup-all.sh --step 0.1
./scripts/setup/setup-all.sh --step 0.2
./scripts/setup/setup-all.sh --step 0.3
./scripts/setup/setup-all.sh --step 0.4
./scripts/setup/setup-all.sh --step 0.5
./scripts/setup/setup-all.sh --step 0.6
```

**Pre-staging shortcut** (all Section 0 steps):

```bash
cd workshop
cp scripts/env/workshop.env.example scripts/env/workshop.env
./scripts/setup/setup-all.sh
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Wrong kubectl context | `./scripts/lib/kubecontext.sh main` or `./scripts/lib/kubecontext.sh upgrade-lab` |
| Expired AWS creds | Refresh SSO or `aws configure` |
| krew not in PATH | Add `~/.krew/bin` to PATH |
| Helm repo 404 in browser | Use CLI only — browser URL may 404 |

## Hands-on variant

Minimum trainee tools: kubectl + shared kubeconfig, or read-only AWS if trainees only observe.

## Install links

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [eksctl](https://eksctl.io/installation/)
- [krew](https://krew.sigs.k8s.io/docs/user-guide/setup/install/)
- [AKO scaling — Karpenter + local volumes](https://aerospike.com/docs/kubernetes/manage/configure/scaling)
- [Helm](https://helm.sh/docs/intro/install/)
