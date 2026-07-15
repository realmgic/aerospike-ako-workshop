# Lab 0.1 — Prerequisites

| Field | Value |
|-------|-------|
| Lab ID | `0.1` |
| Section | Environment Setup |
| EKS cluster | — (client machine only) |
| Duration | ~15 min |
| Validation status | `draft` |

## Takeaway

The instructor client has all required tools, AWS access, and licensing files before touching EKS.

## Prerequisites

- macOS or Linux workstation (or bastion) with network access to AWS
- Aerospike Enterprise **feature-key file** (`features.conf`)

## Steps

1. Clone the workshop repo and open the `workshop/` directory.

2. Copy environment template:

   ```bash
   cd workshop
   cp scripts/env/workshop.env.example scripts/env/workshop.env
   ```

3. Place feature-key file:

   ```bash
   mkdir -p secrets
   cp /path/to/your/features.conf secrets/features.conf
   ```

4. Run client validation:

   ```bash
   ./scripts/setup/01-validate-client.sh
   ```

   **Expected:** All checks print `OK`; exit code 0.

   **Sample output:**

   ```text
   OK  aws
   OK  kubectl
   OK  eksctl
   ...
   Client validation passed.
   ```

## Verify (pass/fail)

1. `aws sts get-caller-identity` returns Account, Arn, UserId
2. `kubectl krew version` succeeds (akoctl is optional here; install in Lab 0.4)
3. `secrets/features.conf` exists

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| AWS identity fails | `aws configure` or refresh SSO |
| krew not found | https://krew.sigs.k8s.io/docs/user-guide/setup/install/ |
| features.conf missing | Obtain from Aerospike licensing portal |

## References

- [Instructor client prerequisites](../../instructor/client-prerequisites.md)

## Teardown / handoff

Proceed to [Lab 0.2 — EKS cluster](02-eks-cluster.md).
