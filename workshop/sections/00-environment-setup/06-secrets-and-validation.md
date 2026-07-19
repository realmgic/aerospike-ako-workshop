# Lab 0.6 — Secrets and Validate Platform

| Field | Value |
|-------|-------|
| Lab ID | `0.6` |
| Section | Environment Setup |
| EKS cluster | `my-cluster` |
| Aerospike cluster | — (none yet) |
| Duration | ~10 min |
| Validation status | `draft` |

## Takeaway

Secrets are deployed and the platform is validated — **no AerospikeCluster yet**; labs deploy their own baseline.

## Prerequisites

- Lab 0.5 complete
- `secrets/features.conf` exists

## Steps

1. Deploy secrets:

   ```bash
   ./scripts/setup/07-deploy-secrets.sh
   ```

   **Expected:** Secrets `aerospike-secret`, `auth-secret`, etc. in `aerospike` namespace.

2. Run environment validation:

   ```bash
   ./scripts/setup/08-validate-environment.sh
   ```

   **Expected:** Exit code 0; message "Environment ready for lab sections." Workload nodepool has `${NODE_COUNT}` Ready nodes. Validation also restarts the local-volume-provisioner (if needed) and checks that local-ssd PVs were discovered.

## Verify (pass/fail)

1. Secrets exist:

   ```bash
   kubectl -n aerospike get secrets
   ```

2. No cluster deployed yet:

   ```bash
   kubectl -n aerospike get aerospikecluster
   ```

   **Pass:** No resources (or empty list).

3. Operator healthy (from 0.3).

4. Workload nodes Ready (from step 0.2-nodes):

   ```bash
   kubectl get nodes -L workshop.aerospike.com/node-pool,node.kubernetes.io/instance-type
   ```

   **Pass:** `${NODE_COUNT}`× `${NODE_TYPE}` nodes Ready.

5. Local-ssd PVs discovered:

   ```bash
   kubectl get pv -o custom-columns=NAME:.metadata.name,CLASS:.spec.storageClassName,CAPACITY:.spec.capacity.storage,STATUS:.status.phase --no-headers | awk '$2 == "local-ssd"'
   ```

   **Pass:** PV count matches instance-type layout × `${NODE_COUNT}` (e.g. 12 PVs for 4× i8g.2xlarge).

## Observe

- `aerospike-secret` contains feature-key file for Enterprise
- Section 1/2 labs call `deploy-cluster.sh` (default storage), `deploy-dim-cluster.sh`, or rack deploy scripts

## Teardown / handoff

**Environment ready.** Proceed to [Section 1 — Scaling & Capacity](../01-scaling-and-capacity/README.md).

## Workshop artifacts

- No AerospikeCluster manifest in this step — secrets via [`scripts/setup/07-deploy-secrets.sh`](../../scripts/setup/07-deploy-secrets.sh)
- Baseline cluster files used in Section 1 (for reference):
  - Path A: [manifests/disk-cluster.yaml](../../manifests/disk-cluster.yaml) (default) · [manifests/dim-cluster.yaml](../../manifests/dim-cluster.yaml) (`--dim`)
  - Path B: [helm/disk-cluster-values.yaml](../../helm/disk-cluster-values.yaml) · [helm/dim-cluster-values.yaml](../../helm/dim-cluster-values.yaml)

## References

- [`scripts/setup/07-deploy-secrets.sh`](../../scripts/setup/07-deploy-secrets.sh)
