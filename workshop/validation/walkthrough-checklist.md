# Walkthrough Validation Checklist

Mark each lab after a full end-to-end run on EKS. Update [LAB_REGISTRY.yaml](../LAB_REGISTRY.yaml) when signing off.

For **Karpenter path** runs, use [karpenter-walkthrough.md](karpenter-walkthrough.md) in addition to this checklist.

## Section 0 — Environment Setup

### eksctl MNG (`NODE_PROVISIONING=eksctl`)

- [ ] **0.1** Prerequisites — `01-validate-client.sh` exits 0
- [ ] **0.2** EKS cluster bootstrap — 4× i8g.2xlarge nodes Ready ([02-eks-cluster.md](../sections/00-environment-setup/02-eks-cluster.md))
- [ ] **0.5** Storage — `ssd` SC + local provisioner + nvme-bootstrap DS + cleanup controller

### Karpenter (`NODE_PROVISIONING=karpenter`)

- [ ] **0.1** Prerequisites — Helm required (Path B / Karpenter)
- [ ] **0.2** Karpenter bootstrap — controller Ready; ≥4 i8g.2xlarge nodes ([02-eks-cluster-karpenter.md](../sections/00-environment-setup/02-eks-cluster-karpenter.md))
- [ ] **0.5** Storage — `ssd` SC + local provisioner + **nvme-bootstrap** DaemonSet

### Both paths

- [ ] **0.3** Install AKO — CSV/Helm release at 4.2.0, operator Running
- [ ] **0.4** Install akoctl — auth create succeeds
- [ ] **0.6** Secrets + validate — secrets exist, no AerospikeCluster CR

## Section 1 — Scaling & Capacity

- [ ] **1.1** Horizontal scaling — size 3→5→3, phase Completed
- [ ] **1.1 (Karpenter)** — observe `nodeclaims` during scale-up
- [ ] **1.2** Rack awareness + vertical scale + revision — pods include rack ID; `nodeSelector` baseline→vertical; nodes i8g.4xlarge, memory 115Gi, pods on v2 revision, 2× local-ssd PVCs per pod
- [ ] **1.3** Rack replacement (standalone) — racks 3+4 only on vertical 4xl; memory 115Gi; no rack 1/2 pods

## Section 2 — Maintenance & Upgrade

- [ ] **2.1** akoctl — install, collectinfo tarball created (optional: config flags, auth)
- [ ] **2.2** Upgrade AKO — ladder 4.2.0→4.5.0, Aerospike stays Running on 8.1.0.x

## Lab 1.4 (after 2.2)

- [ ] **1.4** Replication factor — RF 2→3 dynamic, no pod restart *(requires AKO 4.4.0+ from Lab 2.2)*

## Section 2 — Maintenance & Upgrade (continued)
- [ ] **2.3** Upgrade Aerospike DB — 8.1.0.x→8.1.2.x, rolling restart
- [ ] **2.4** On-demand operations — PodRestart (cold) then WarmRestart on dim 8.1.2.x
- [ ] **2.5** K8s node maintenance — data loaded; pod held on node during `InProgress`; drain succeeds after `Completed`
- [ ] **2.5 (eksctl only)** — blocklist path validated (same migration observation)
- [ ] **2.5 (Karpenter only)** — drain + optional disruption; **no blocklist**
- [ ] **2.5 (Karpenter only) add-on** — do-not-disrupt graduation + `terminationGracePeriod` (instructor-led)
- [ ] **2.6** K8s control plane upgrade — 3 pods Running through upgrade (upgrade-lab eksctl cluster)

## Path coverage

- [ ] Path A (OLM/kubectl) validated for all applicable labs
- [ ] Path B (Helm) validated for all applicable labs
- [ ] Node provisioning: eksctl MNG validated
- [ ] Node provisioning: Karpenter validated ([karpenter-walkthrough.md](karpenter-walkthrough.md))

## Sign-off

| Field | Value |
|-------|-------|
| Validator | |
| Date | |
| NODE_PROVISIONING | eksctl / karpenter |
| AKO version tested | |
| K8s version tested | |
| Notes | |
