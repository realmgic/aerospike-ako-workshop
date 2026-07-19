# Lab 0.3 — Install AKO (Path B: Helm)

| Field | Value |
|-------|-------|
| Lab ID | `0.3` |
| Section | Environment Setup |
| EKS cluster | `my-cluster` |
| AKO version | `4.2.0` |
| Deploy path | B (Helm) |
| Duration | ~20 min |
| Validation status | `draft` |

## Takeaway

AKO is installed via Helm at version **4.2.0** with cert-manager and safe pod eviction enabled.

## Prerequisites

- Lab 0.2 complete
- `DEPLOY_PATH=helm` in workshop.env
- Helm 3.12+

## Steps

1. Install cert-manager and AKO:

   ```bash
   ./scripts/setup/03-install-ako.sh
   ```

2. Verify Helm release:

   ```bash
   helm list -n operators
   ```

   **Expected:** `aerospike-kubernetes-operator` at chart version `4.2.0`, status `deployed`.

3. Verify operator pods:

   ```bash
   kubectl -n operators get pods
   ```

   **Expected:** Controller manager `Running`.

## Verify (pass/fail)

```bash
helm list -n operators -o json | jq '.[0].chart'
```

**Pass:** Chart string contains `4.2.0`.

Key values in [helm/operator-values.yaml](../../helm/operator-values.yaml): `watchNamespaces=aerospike`, `safePodEviction.enable=true`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Webhook errors on CR apply | Wait for cert-manager pods Ready |
| Helm repo 404 in browser | Normal — use `helm repo add` CLI only |

## Not covered here

OLM install → [03-install-ako-olm.md](03-install-ako-olm.md)

## Teardown / handoff

Proceed to [Lab 0.4 — akoctl](04-install-akoctl.md).

## Workshop artifacts

- Path B: [helm/operator-values.yaml](../../helm/operator-values.yaml)

## References

- [Install AKO via Helm](https://aerospike.com/docs/kubernetes/install/helm/)
