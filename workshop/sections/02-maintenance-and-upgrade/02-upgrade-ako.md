# Lab 2.2 — Upgrade AKO (Sequential)


| Field              | Value                                                                                         |
| ------------------ | --------------------------------------------------------------------------------------------- |
| Lab ID             | `2.2`                                                                                         |
| Section            | Maintenance & Upgrade                                                                         |
| EKS cluster        | `my-cluster`                                                                                  |
| AKO ladder         | `4.2.0 → 4.3.0 → 4.4.1 → 4.5.0`                                                               |
| Aerospike baseline | 3-node cluster Running during upgrade (**8.1.0.x**)                                           |
| Deploy path        | both                                                                                          |
| Duration           | ~30–40 min (full ladder); demo one step live                                                  |
| Validation status  | `draft`                                                                                       |
| Official docs      | [Upgrading operator](https://aerospike.com/docs/kubernetes/manage/upgrade/upgrading-operator) |


## Takeaway

AKO must be upgraded **one version at a time** — each release updates chart/bundle **and** CRDs. Skipping versions risks CRD, webhook, and controller drift.

## Prerequisites

- Section 0 installed AKO at **4.2.0**
- 3-node cluster Running on **8.1.0.x** (from [Lab 2.1](01-akoctl.md) — `./scripts/labs/prepare-lab.sh 2.1` if coming from Section 1):

```bash
kubectl -n aerospike get pods
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'
```

**Expected:** 3/3 pods `Running`; phase `Completed`.



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

### Manual equivalent (OLM, one step)

Replace `<VERSION>` with each ladder target (`4.3.0`, `4.4.1`, `4.5.0`). The script sets `startingCSV` so OLM creates an InstallPlan for that exact step (do not skip versions).

```bash
source scripts/env/workshop.env   # OPERATOR_NAMESPACE, etc.
export CSV_TARGET="aerospike-kubernetes-operator.v<VERSION>"

# 1. Pin subscription to the target CSV (triggers InstallPlan)
kubectl patch subscription aerospike-kubernetes-operator -n "${OPERATOR_NAMESPACE}" --type merge \
  -p "{\"spec\":{\"startingCSV\":\"${CSV_TARGET}\"}}"

# 2. Approve the InstallPlan OLM creates for that CSV
kubectl get installplan -n "${OPERATOR_NAMESPACE}" | grep aerospike
kubectl patch installplan <INSTALLPLAN_NAME> -n "${OPERATOR_NAMESPACE}" --type merge \
  -p '{"spec":{"approved":true}}'

# 3. Wait for the new CSV
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  "csv/${CSV_TARGET}" -n "${OPERATOR_NAMESPACE}" --timeout=600s

# 4. Verify operator + dim cluster still healthy
kubectl get csv -n "${OPERATOR_NAMESPACE}" | grep "${CSV_TARGET}"
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'
kubectl -n aerospike get pods
```

**Expected per step:** CSV `Succeeded`; subscription `currentCSV` matches target; Aerospike CR still `Completed`.



## Steps — Path B (Helm)

For each target version:

```bash
./scripts/labs/upgrade-ako/upgrade-step-helm.sh 4.3.0
./scripts/labs/upgrade-ako/upgrade-step-helm.sh 4.4.1
./scripts/labs/upgrade-ako/upgrade-step-helm.sh 4.5.0
```

CRDs are replaced before each `helm upgrade` — **never** `kubectl delete` CRDs.

Or run full ladder:

```bash
./scripts/labs/upgrade-ako/upgrade-all-helm.sh
```

### Manual equivalent (Helm, one step)

Replace `<VERSION>` with each ladder target. CRDs must be **replaced** (not deleted) before the chart upgrade.

```bash
source scripts/env/workshop.env   # OPERATOR_NAMESPACE, HELM_OPERATOR_RELEASE, etc.
export TARGET="<VERSION>"

# 1. Replace CRDs from the target operator tag
for crd in aerospikeclusters aerospikebackupservices aerospikebackups aerospikerestores; do
  kubectl replace -f \
    "https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/v${TARGET}/config/crd/bases/asdb.aerospike.com_${crd}.yaml"
done

# 2. Upgrade operator chart (workshop values pin watchNamespaces, safePodEviction, etc.)
helm repo update
helm upgrade "${HELM_OPERATOR_RELEASE}" aerospike/aerospike-kubernetes-operator \
  --namespace "${OPERATOR_NAMESPACE}" \
  --version="${TARGET}" \
  -f helm/operator-values.yaml

# 3. Wait for controller rollout
kubectl -n "${OPERATOR_NAMESPACE}" rollout status \
  deployment/aerospike-operator-controller-manager --timeout=300s

# 4. Verify
helm list -n "${OPERATOR_NAMESPACE}" | grep "${HELM_OPERATOR_RELEASE}"
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}{"\n"}'
kubectl -n aerospike get pods
```

**Expected per step:** Helm release shows `<VERSION>`; controller Ready; Aerospike CR still `Completed`.

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

