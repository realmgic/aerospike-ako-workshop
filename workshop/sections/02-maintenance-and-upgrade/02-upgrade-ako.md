# Lab 2.2 — Upgrade AKO (Sequential)


| Field              | Value                                                                                         |
| ------------------ | --------------------------------------------------------------------------------------------- |
| Lab ID             | `2.2`                                                                                         |
| Section            | Maintenance & Upgrade                                                                         |
| EKS cluster        | `my-cluster`                                                                                  |
| AKO ladder         | `4.2.0 → 4.3.0 → 4.4.1 → 4.5.0`                                                               |
| Aerospike baseline | dim 3-node Running during upgrade (**8.1.0.x**)                                               |
| Deploy path        | both                                                                                          |
| Duration           | ~30–40 min (full ladder); demo one step live                                                  |
| Validation status  | `draft`                                                                                       |
| Official docs      | [Upgrading operator](https://aerospike.com/docs/kubernetes/manage/upgrade/upgrading-operator) |


## Takeaway

AKO must be upgraded **one version at a time** — each release updates chart/bundle **and** CRDs. Skipping versions risks CRD, webhook, and controller drift.

## Prerequisites

- Section 0 installed AKO at **4.2.0**
- 3-node dim cluster Running on **8.1.0.x** (compatible with AKO 4.2.0):
  ```bash
  ./scripts/labs/deploy-dim-cluster.sh
  # applies manifests/dim-cluster.yaml
  # or: kubectl apply -f manifests/dim-cluster.yaml
  kubectl -n aerospike get pods
  ```



## Background


| What changes each version | Risk if skipped                  |
| ------------------------- | -------------------------------- |
| Helm chart / OLM bundle   | Deployment, webhooks, RBAC drift |
| CRD definitions           | Validation failures              |
| Controller logic          | Reconcile errors                 |


Training ladder (no versions before 4.2.0):

```text
4.2.0 → 4.3.0 → 4.4.1 → 4.5.0
```

Section 0 installs **4.2.0**. Lab 2.2 runs upgrade steps **4.3.0**, **4.4.1**, then **4.5.0**.

**OperatorHub note:** the stable channel offers **4.4.1** (not 4.4.0) as the patch upgrade after 4.3.0. The training ladder uses 4.4.1 for the OLM path.

**DB version note:** Aerospike stays at **8.1.0.x** throughout this lab. AKO 4.5.0 adds support for 8.1.2.x — the DB upgrade is [Lab 2.3](03-upgrade-aerospike-db.md).

## Steps — Path A (OLM)

For each target version (`4.3.0`, `4.4.1`, `4.5.0`):

```bash
./scripts/labs/upgrade-ako/upgrade-step-olm.sh 4.3.0
./scripts/labs/upgrade-ako/verify-ako-version.sh 4.3.0
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}'
```

Repeat for `4.4.1` and `4.5.0`.

**Expected per step:** CSV phase `Succeeded`; Aerospike cluster still `Completed`; pods `Running`.

Or run full ladder:

```bash
./scripts/labs/upgrade-ako/upgrade-all-olm.sh
```



## Steps — Path B (Helm)

For each target version:

```bash
./scripts/labs/upgrade-ako/upgrade-step-helm.sh 4.3.0
./scripts/labs/upgrade-ako/upgrade-step-helm.sh 4.4.1
./scripts/labs/upgrade-ako/upgrade-step-helm.sh 4.5.0
```

CRDs are replaced before each `helm upgrade` — **never** `kubectl delete` CRDs.

## Verify (pass/fail)

After reaching 4.5.0:

```bash
./scripts/labs/upgrade-ako/verify-ako-version.sh 4.5.0
kubectl -n aerospike get pods
```

**Pass:** AKO 4.5.0; 3/3 Aerospike pods Running; CR `Completed`; DB image still **8.1.0.x**.

## Observe

- Operator pod rolling restart each step
- Aerospike pods unchanged throughout AKO upgrade



## Short demo path

If time-limited: demo **4.2.0 → 4.3.0** live; pre-stage **4.4.1** and **4.5.0**; state production must follow [official ladder](https://aerospike.com/docs/kubernetes/manage/upgrade/upgrading-operator).

## Not covered here

- DB upgrade → [Lab 2.3](03-upgrade-aerospike-db.md)
- Control plane → [Lab 2.6](06-k8s-control-plane-upgrade.md)



## Teardown / handoff

**Required before Lab 1.5** (needs AKO 4.4.0+ — satisfied after the 4.4.1 step). Proceed to [Lab 1.5](../01-scaling-and-capacity/05-replication-factor.md) or continue 2.3–2.6.

## References

- [Upgrade AKO OLM](https://aerospike.com/docs/kubernetes/manage/upgrade/olm/)
- [Upgrade AKO Helm](https://aerospike.com/docs/kubernetes/manage/upgrade/helm/)

