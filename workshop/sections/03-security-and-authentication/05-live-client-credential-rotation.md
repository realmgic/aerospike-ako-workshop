# Lab 3.5 — Live Client Credential Rotation

| Field              | Value |
| ------------------ | ----- |
| Lab ID             | `3.5` |
| Section            | Security & Authentication |
| AKO min version    | `4.2.0` |
| Duration           | ~25 min |
| Validation status  | `draft` |

## Takeaway

Rotate client credentials with **overlap**: deploy v2 cert, roll workload, then **`cert-blacklist`** to revoke v1 — authentication stays available throughout the overlap window.

## Background

Client credential rotation is an **Aerospike PKI procedure** on top of K8s secret delivery:

1. **Overlap** — v1 and v2 are both signed by the same CA, same CN (`app`), different serials. Aerospike accepts both until v1 is revoked.
2. **Roll clients to v2** — patch `tls-client-app-secret` and restart the workload Job so it mounts the new cert material.
3. **Revoke v1** — set `security.cert-blacklist` with the v1 serial. This is native **Aerospike** revocation, not an AKO feature.

[`apply-cert-blacklist.sh`](../../scripts/labs/apply-cert-blacklist.sh) applies [`manifests/*-cluster-tls-mtls-blacklist.yaml`](../../manifests/disk-cluster-tls-mtls-blacklist.yaml) — a **CR change** (blacklist volume + `security.cert-blacklist`). First-time blacklist setup may reconcile differently from a pure secret patch in Lab 3.4.

**Scope:** this lab rotates the **`app`** client cert only. `admin`, `exporter`, and `ako-operator` use separate secrets and are not rotated here.

## Why access is preserved

- **Order matters:** prove v2 works **before** blacklisting v1. The overlap window is intentional.
- **Auth continuity:** during overlap, either certificate authenticates as user `app`. Apply the blacklist only after the v2 workload connects successfully.
- **Same CA and CN** — clients keep the same trust store and username mapping; only the certificate serial changes.

## Prerequisites

- Lab **3.4** (or **3.3** with PKI workload running)

## Phase 0 — Prepare lab

```bash
./scripts/labs/prepare-lab.sh 3.5 --skip-reset
./scripts/labs/run-lab-workload.sh --pki start
```

## Steps

### Save v1 client cert, generate v2

```bash
./scripts/setup/tls/rotate-client-cert.sh --save-v1
```

Both v1 and v2 are valid until blacklist is applied.

### Roll workload to v2

```bash
./scripts/labs/rotate-client-workload.sh
```

Confirm v2 connection works; v1 still works (overlap window).

Test v1 explicitly (optional):

```bash
asadm -h "aerocluster:aerocluster:4333" --tls-enable \
  --tls-cafile secrets/tls/cacert.pem \
  --tls-certfile secrets/tls/app-v1.pem --tls-keyfile secrets/tls/app-v1.key \
  --auth PKI -e "info"
```

### Apply cert blacklist for v1

```bash
./scripts/labs/apply-cert-blacklist.sh --cert secrets/tls/app-v1.pem
```

## Verify

| Check | Pass criteria |
|-------|---------------|
| **Auth overlap** | v1 PKI login works before blacklist; v2 workload connects; v1 connection **rejected** after blacklist |
| **Workload continuity** | TPS may dip briefly during Job stop/start ([`rotate-client-workload.sh`](../../scripts/labs/rotate-client-workload.sh)). **Authentication** stays available throughout overlap — do not conflate PKI overlap with a seamless TPS handoff |

True zero-TPS client rollover would require overlapping clients (two Jobs) or application-level reconnect logic — out of scope for this lab.

## Workshop artifacts

| Script | Purpose |
|--------|---------|
| `scripts/setup/tls/rotate-client-cert.sh --save-v1` | Overlap rotation |
| `scripts/labs/rotate-client-workload.sh` | Restart Job with new secret |
| `scripts/labs/apply-cert-blacklist.sh` | Deploy blacklist + CR patch |
| `manifests/*-cluster-tls-mtls-blacklist.yaml` | CR with `security.cert-blacklist` |

## References

- [Certificate blacklist](https://aerospike.com/docs/server/operations/configure/security/pki/)
