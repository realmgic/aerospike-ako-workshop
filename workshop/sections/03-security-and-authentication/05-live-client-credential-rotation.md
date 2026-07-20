# Lab 3.5 — Live Client Credential Rotation

| Field              | Value |
| ------------------ | ----- |
| Lab ID             | `3.5` |
| Section            | Security & Authentication |
| EKS cluster        | `my-cluster` |
| Aerospike cluster  | `aerocluster` |
| AKO min version    | `4.2.0` |
| Aerospike baseline | 3-node **8.1.0.0** mTLS + PKIOnly (continues from Lab 3.4) |
| Deploy path        | both |
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

### Secret updates and pod recreation

Not every step in this lab affects Aerospike DB pods the same way:

| Step | What changes | Aerospike DB pods recreated? | What restarts instead |
|------|----------------|------------------------------|------------------------|
| `rotate-client-cert.sh --save-v1` | `tls-client-app-secret` data | **No** — app client secret is not mounted on DB pods | Nothing (overlap: v1 still valid server-side) |
| `rotate-client-workload.sh` | Workload picks up v2 from Secret | **No** | **asbench Job** stop/start (intentional) |
| `apply-cert-blacklist.sh` | CR + `tls-cert-blacklist-secret` | **Possibly yes** — first-time blacklist volume + `security.cert-blacklist` is a **CR schema change** | AKO may rolling-restart to apply new volume/config |

Patching `tls-client-app-secret` alone follows the same Kubernetes pattern as Lab 3.4: the kubelet updates mounted files on pods that reference the Secret. The workshop workload Job is restarted separately so asbench reads the new cert — that is **client** pod recreation, not an AKO-driven DB pod roll.

## Why access is preserved

- **Order matters:** prove v2 works **before** blacklisting v1. The overlap window is intentional.
- **Auth continuity:** during overlap, either certificate authenticates as user `app`. Apply the blacklist only after the v2 workload connects successfully.
- **Same CA and CN** — clients keep the same trust store and username mapping; only the certificate serial changes.

## Prerequisites

- Lab **3.4** (or **3.3** with PKI workload running)

## Node requirements

| Item | Value |
|------|-------|
| Instance | `i8g.2xlarge` baseline pool (same as Section 1) |
| Reset | **Skip** (default) — client cert overlap on live cluster; reuses node pools |
| Node pools | Unchanged from Labs 3.1–3.4 |

## Phase 0 — Prepare lab

**What:** Start PKI workload on the current (v1) client cert before rotation.
**Credential / mode:** Client cert `app.pem` (v1) via `--pki`.
**Run:**

```bash
./scripts/labs/prepare-lab.sh 3.5 --skip-reset
./scripts/labs/run-lab-workload.sh --pki start
```

**Expect:** asbench Job running with v1 cert; steady TPS.

## Steps

### Step 1 — Save v1, generate v2

**What:** Copy current cert to `app-v1.pem`; generate new `app.pem` (v2); patch `tls-client-app-secret`.
**Credential / mode:** v1 saved to `secrets/tls/app-v1.pem` + `tls-client-app-v1-secret`; v2 active in `tls-client-app-secret`.
**Run:**

```bash
./scripts/setup/tls/rotate-client-cert.sh --save-v1
```

The script saves v1, deploys `tls-client-app-v1-secret`, generates v2, and patches `tls-client-app-secret`. Compare serials:

```bash
echo "v1 (saved):" && openssl x509 -in secrets/tls/app-v1.pem -noout -serial
echo "v2 (active):" && openssl x509 -in secrets/tls/app.pem -noout -serial
```

**Expect:** Two different serials; script confirms "Server accepts both until blacklist is applied". Workload still uses v1 until Step 2.

### Step 2 — Roll workload to v2

**What:** Stop and restart the asbench Job so it mounts v2 from `tls-client-app-secret`.
**Credential / mode:** Workload switches from v1 (`app-v1.pem`) to v2 (`app.pem`).
**Run:**

```bash
./scripts/labs/rotate-client-workload.sh
./scripts/labs/run-lab-workload.sh status
```

**Expect:** TPS resumes with no auth errors — workload now authenticates with v2. Server still accepts v1 too (overlap window open).

### Step 3 — Prove overlap: v1 still works

**What:** Connect with the **saved v1 cert** while the v2 workload from Step 2 is still running — proves both serials are valid server-side.
**Credential / mode:** Client cert **v1** (`app-v1.pem` from `tls-client-app-v1-secret`); PKI auth only.
**Run:**

```bash
kubectl -n aerospike run aerospike-tool-v1 --rm --attach --restart=Never \
  --image=aerospike/aerospike-tools:latest \
  --overrides='{"spec":{"containers":[{"name":"aerospike-tool-v1","image":"aerospike/aerospike-tools:latest",
    "command":["asadm"],
    "args":["-h","aerocluster:aerocluster:4333","--tls-enable","--tls-cafile","/etc/aerospike/tls/ca/cacert.pem","--tls-certfile","/etc/aerospike/tls/client/app.pem","--tls-keyfile","/etc/aerospike/tls/client/app.key","--auth","PKI","-e","info"],
    "volumeMounts":[{"name":"tls-ca","mountPath":"/etc/aerospike/tls/ca","readOnly":true},{"name":"tls-client-v1","mountPath":"/etc/aerospike/tls/client","readOnly":true}]}],
    "volumes":[{"name":"tls-ca","secret":{"secretName":"tls-ca-secret"}},{"name":"tls-client-v1","secret":{"secretName":"tls-client-app-v1-secret"}}]}}'
```

**Expect:** PKI login succeeds with v1 — overlap confirmed. Both v1 and v2 authenticate as user `app` at the same time.

### Step 4 — Blacklist v1 serial

**What:** Revoke v1 server-side by adding its serial to `security.cert-blacklist`.
**Credential / mode:** Server rejects v1 serial; v2 still trusted.
**Run:**

```bash
./scripts/labs/apply-cert-blacklist.sh --cert secrets/tls/app-v1.pem
```

**Expect:** Script prints the blacklisted serial (matches v1 from Step 1). v2 workload should continue unaffected.

### Step 5 — Prove v1 rejected

**What:** Re-run the **same** Step 3 command — v1 should now fail.
**Credential / mode:** Client cert **v1** (`app-v1.pem`) — same as Step 3.
**Run:** Repeat the `kubectl run aerospike-tool-v1 …` command from Step 3.

**Expect:** Login **fails** (`Not able to connect` or auth error). v2 workload from Step 2 still running — run `./scripts/labs/run-lab-workload.sh status` to confirm TPS.

## Verify

| Step | Check | Pass criteria |
|------|-------|---------------|
| 1 | Two serials exist | v1 and v2 serials differ; script confirms overlap window |
| 2 | Workload on v2 | TPS resumes after Job restart; no auth errors |
| 3 | Overlap proof | v1 PKI login **succeeds** while v2 workload runs |
| 4 | Blacklist applied | Script prints v1 serial in `revoked.txt` |
| 5 | v1 revoked | Same Step 3 command **fails**; v2 workload still healthy |

True zero-TPS client rollover would require overlapping clients (two Jobs) or application-level reconnect logic — out of scope for this lab.

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| v1 still works after blacklist | Wrong serial in `revoked.txt` — re-run `apply-cert-blacklist.sh` with correct `--cert` path |
| Aerospike pods rolled during client cert patch | Unexpected if only `tls-client-app-secret` changed — check for accidental CR edits |
| Aerospike pods rolled during blacklist step | Expected on first blacklist CR apply — plan for brief reconcile; auth overlap should cover client access |

## Workshop artifacts

- [scripts/setup/tls/rotate-client-cert.sh](../../scripts/setup/tls/rotate-client-cert.sh) — overlap rotation (use `--save-v1`)
- [scripts/labs/rotate-client-workload.sh](../../scripts/labs/rotate-client-workload.sh) — restart Job with new secret
- [scripts/labs/apply-cert-blacklist.sh](../../scripts/labs/apply-cert-blacklist.sh) — deploy blacklist + CR patch
- [scripts/labs/run-lab-workload.sh](../../scripts/labs/run-lab-workload.sh) — background PKI workload (`--pki`)
- **Cert blacklist CR (Path A):**
  - [manifests/disk-cluster-tls-mtls-blacklist.yaml](../../manifests/disk-cluster-tls-mtls-blacklist.yaml) (default) · [manifests/dim-cluster-tls-mtls-blacklist.yaml](../../manifests/dim-cluster-tls-mtls-blacklist.yaml) (`--dim`)
  - Path B: [helm/disk-cluster-tls-mtls-blacklist-values.yaml](../../helm/disk-cluster-tls-mtls-blacklist-values.yaml) · [helm/dim-cluster-tls-mtls-blacklist-values.yaml](../../helm/dim-cluster-tls-mtls-blacklist-values.yaml)

## References

- [Certificate blacklist](https://aerospike.com/docs/server/operations/configure/security/pki/)
