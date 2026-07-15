# Walkthrough Validation

Run a full end-to-end walkthrough of every lab on a real EKS environment before delivery.

## Process

1. **Draft** — guide written; `validation_status: draft` in [LAB_REGISTRY.yaml](../LAB_REGISTRY.yaml)
2. **Walkthrough run** — instructor executes every step; note drift in the guide
3. **Fix** — update commands and expected outputs until reproducible
4. **Sign-off** — set `validation_status: validated`, `validated_on` date, and `validated_with` AKO/K8s versions
5. **Refresh** — after AKO or EKS version bumps, re-run affected labs; mark `needs-refresh` until done

## Prerequisites for validation

- Main cluster `my-cluster`:
  - **eksctl path:** workload nodes from Lab 1.1; vertical scale to i8g.4xlarge in Lab 1.3, K8s 1.32
  - **Karpenter path:** system MNG; NodePool from Lab 1.1; additive `${KARPENTER_NODEPOOL_VERTICAL_NAME}` in Lab 1.3 Phase 2 — see [karpenter-walkthrough.md](karpenter-walkthrough.md)
- Upgrade-lab cluster `my-cluster-k8s-upgrade` (3× i8g.2xlarge, K8s 1.31→1.32) for Lab 2.6 only — **always eksctl MNG**
- Valid `features.conf` at path referenced in `scripts/setup/07-deploy-secrets.sh`
- Both deploy paths (OLM/Helm) validated separately (or document N/A)
- Both node provisioning paths (eksctl/Karpenter) validated separately for main cluster

## Node provisioning validation matrix

| Path | Checklist | Registry key |
|------|-----------|--------------|
| eksctl MNG | [walkthrough-checklist.md](walkthrough-checklist.md) | default |
| Karpenter | [karpenter-walkthrough.md](karpenter-walkthrough.md) | `karpenter_validation` in LAB_REGISTRY |

## Tools

```bash
# Run a lab's verify script block (when defined)
./scripts/validation/run-lab-verify.sh 1.1

# Shared cluster health check
./scripts/verify-cluster.sh
```

## Recording results

Update the lab entry in `LAB_REGISTRY.yaml`:

```yaml
validation_status: validated
validated_on: "2026-07-14"
validated_with:
  ako: "4.5.0"
  k8s: "1.32"
  node_provisioning: karpenter   # when applicable
```

For Karpenter path sign-off, also update the `karpenter_validation` block at the bottom of `LAB_REGISTRY.yaml`.

Optionally save command output under `validation/expected/` for diff during refresh.

See [walkthrough-checklist.md](walkthrough-checklist.md) for per-lab checkboxes.
