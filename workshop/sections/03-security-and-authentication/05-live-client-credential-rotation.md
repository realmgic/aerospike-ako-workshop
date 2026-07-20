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

Test v1 explicitly (optional). `aerocluster` is a headless Service and only resolves inside the cluster, and `app-v1.pem`/`app-v1.key` are local-only files (not a deployed Secret), so stage them into a temporary Secret and mount it into a debug pod:

```bash
kubectl -n aerospike create secret generic tls-client-app-v1-secret \
  --from-file=app-v1.pem=secrets/tls/app-v1.pem \
  --from-file=app-v1.key=secrets/tls/app-v1.key \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n aerospike run aerospike-tool-v1 --rm --attach --restart=Never \
  --image=aerospike/aerospike-tools:latest \
  --overrides='{"spec":{"containers":[{"name":"aerospike-tool-v1","image":"aerospike/aerospike-tools:latest",
    "command":["asadm"],
    "args":["-h","aerocluster:aerocluster:4333","--tls-enable","--tls-cafile","/etc/aerospike/tls/ca/cacert.pem","--tls-certfile","/etc/aerospike/tls/client/app-v1.pem","--tls-keyfile","/etc/aerospike/tls/client/app-v1.key","--auth","PKI","-e","info"],
    "volumeMounts":[{"name":"tls-ca","mountPath":"/etc/aerospike/tls/ca","readOnly":true},{"name":"tls-client-v1","mountPath":"/etc/aerospike/tls/client","readOnly":true}]}],
    "volumes":[{"name":"tls-ca","secret":{"secretName":"tls-ca-secret"}},{"name":"tls-client-v1","secret":{"secretName":"tls-client-app-v1-secret"}}]}}'

kubectl -n aerospike delete secret tls-client-app-v1-secret
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
