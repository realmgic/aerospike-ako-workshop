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

   **Expected:** Exit code 0; message "Environment ready for lab sections."

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

## Observe

- `aerospike-secret` contains feature-key file for Enterprise
- Section 1/2 labs call `deploy-dim-cluster.sh` or rack deploy scripts

## Teardown / handoff

**Environment ready.** Proceed to [Section 1 — Scaling & Capacity](../01-scaling-and-capacity/README.md).

## References

- [`scripts/setup/07-deploy-secrets.sh`](../../scripts/setup/07-deploy-secrets.sh)
