# Karpenter Path Walkthrough Checklist

Run the **full main-cluster curriculum** with `NODE_PROVISIONING=karpenter` before signing off the Karpenter path. Lab 2.6 still uses the separate upgrade-lab cluster on eksctl MNG.

Update [LAB_REGISTRY.yaml](../LAB_REGISTRY.yaml) `karpenter_validation` when complete.

## Pre-flight

- [ ] `NODE_PROVISIONING=karpenter` in `workshop.env`
- [ ] `KARPENTER_CONSOLIDATION=Off` for live run (optional: `WhenEmpty` for consolidation demo)
- [ ] Helm 3.12+ installed
- [ ] EC2 quota for 4–8× `i8g.2xlarge` + 2× `t3.large` (baseline)
- [ ] EC2 quota for 4–8× `i8g.4xlarge` (Lab 1.2 Phase 2; up to 8 nodes with idle baseline pool)

## Section 0 — Environment Setup (Karpenter)

- [ ] **0.1** Prerequisites — `01-validate-client.sh` exits 0 (Helm required)
- [ ] **0.2** Karpenter bootstrap — controller Ready; ≥4 i8g workload nodes; [02-eks-cluster-karpenter.md](../sections/00-environment-setup/02-eks-cluster-karpenter.md)
- [ ] **0.3** Install AKO — CSV/Helm release at 4.2.0
- [ ] **0.4** Install akoctl — auth create succeeds
- [ ] **0.5** Storage — `ssd` SC + local provisioner + **nvme-bootstrap** DS + cleanup controller Ready
- [ ] **0.6** Secrets + validate — `08-validate-environment.sh` passes Karpenter gates

## Section 1 — Scaling & Capacity

- [ ] **1.1** Horizontal scaling — `load-data.sh` (5M records); scale 3→5; observe `kubectl get nodeclaims -w`; scale back to 3; migration wait on scale-down
- [ ] **1.2** Rack awareness + vertical scale + revision — additive 4xl NodePool; `nodeSelector` baseline→vertical; pods on `i8g.4xlarge`; memory 115Gi; revision v2; 2× `local-ssd` PVCs per pod
- [ ] **1.3** Rack replacement (standalone) — light reset; v1 on baseline pool; vertical pool; racks 3+4 replace 1+2; same 2× vertical profile as 1.2 v2

## Section 2 — Maintenance & Upgrade

- [ ] **2.1** akoctl — collectinfo tarball created
- [ ] **2.2** Upgrade AKO — ladder 4.2.0→4.5.0

## Lab 1.4 (after 2.2)

- [ ] **1.4** Replication factor — RF 2→3 then 3→2 dynamic *(requires AKO 4.4.0+ from Lab 2.2)*

## Section 2 — Maintenance & Upgrade (continued)
- [ ] **2.3** On-demand operations — WarmRestart then PodRestart (cold) on 8.1.0.x cluster; optional `run-lab-workload.sh` in Terminal B
- [ ] **2.4** Upgrade Aerospike DB — 8.1.0.x→8.1.2.x rolling restart; `run-lab-workload.sh` ~10k TPS through upgrade
- [ ] **2.5** Karpenter maintenance — data loaded (`load-data.sh` or `prepare-lab.sh 2.5 --load-data`); pod held during `InProgress`; drain after `Completed`; **no blocklist**
- [ ] **2.5 add-on** — do-not-disrupt graduation discussion; three protection layers; `terminationGracePeriod` sizing (instructor-led)
- [ ] **2.6** Control plane upgrade — **upgrade-lab eksctl cluster**; optional `run-lab-workload.sh --upgrade-lab` in Terminal B

## Path coverage (Karpenter + deploy path)

- [ ] Karpenter + Path A (OLM/kubectl)
- [ ] Karpenter + Path B (Helm) — if offering both deploy paths on Karpenter

## Sign-off

| Field | Value |
|-------|-------|
| Validator | |
| Date | |
| NODE_PROVISIONING | karpenter |
| KARPENTER_VERSION | |
| AKO version tested | |
| K8s version tested | |
| Notes | |

## Record in LAB_REGISTRY

After sign-off, set:

```yaml
karpenter_validation:
  status: validated   # or draft until run
  validated_on: YYYY-MM-DD
  validated_with:
    karpenter: "1.x.x"
    ako: "4.5.0"
    k8s: "1.33"   # match K8S_VERSION in workshop.env
  validator: "<name>"
```

Per-lab `validation_status` for Karpenter runs can be noted in lab entries' `validated_with.node_provisioning: karpenter`.
