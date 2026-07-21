# Lab 3.4 — Server Certificate Rotation

| Field              | Value |
| ------------------ | ----- |
| Lab ID             | `3.4` |
| Section            | Security & Authentication |
| EKS cluster        | `my-cluster` |
| Aerospike cluster  | `aerocluster` |
| AKO min version    | `4.2.0` |
| Aerospike baseline | 3-node **8.1.0.0** mTLS + PKI (continues from Lab 3.3) |
| Deploy path        | both |
| Duration           | ~20 min |
| Validation status  | `draft` |

## Takeaway

Rotate the **service TLS** server certificate in place by patching `tls-server-secret` — workload continues without pod restart.

## Background

Certificate rotation here uses **two layers** — K8s/AKO for delivery, Aerospike for runtime reload:

```text
K8s / AKO (delivery)          Aerospike (runtime)
─────────────────────         ────────────────────
tls-server-secret mounted     Reads cert files from
via CR storage.volumes        /etc/aerospike/tls/
Patch secret in place    →    Hot-reloads cert content
(same secret name)              without pod restart
```

This lab rotates the **server** cert (`svc_chain.pem`), not the client cert. Client auth is unaffected:

```text
Before rotation          After rotation
────────────────         ────────────────
svc_chain.pem (serial A) svc_chain.pem (serial B)  ← new file, same secret name
app.pem unchanged        app.pem unchanged         ← client auth unaffected
```

- There is **no AKO “rotate certificate” API** — rotation is regenerate with OpenSSL, then `kubectl apply` the **same** Secret name.
- AKO’s role is **volume mount delivery** only. Hitless server rotation is **Aerospike TLS file reload** (see [References](#references)).
- **Contrast with Labs 3.2/3.3:** changing `network.tls[]`, `tls-authenticate-client`, or `authMode` is a **CR schema change** → AKO **rolling restart**. Lab 3.4 only changes **secret content** at the same mount path — no CR edit required.

### Secret updates and pod recreation

Patching Secret **data** in place (same Secret name, same CR volume reference) does **not** recreate Aerospike pods:

1. **Kubernetes** — the kubelet syncs updated Secret bytes into the existing volume mount (often after a short delay; allow ~60s).
2. **AKO** — does not reconcile, because the `AerospikeCluster` spec is unchanged.
3. **Aerospike** — reloads cert files from the mount path without restarting the process.

| Change | Aerospike pods recreated? |
|--------|---------------------------|
| Patch Secret **data** only (`tls-server-secret`, same `secretName` in CR) | **No** |
| Change CR: `secretName`, mount path, new volume, `network.tls[]`, `authMode`, etc. | **Yes** — AKO rolling restart |
| Delete pod manually | **Yes** (replacement pod) |

If pods roll after “rotation,” check whether the **CR** changed — not just the Secret content.

### What the rotation scripts do

Lab Step 2 uses [`rotate-server-cert.sh`](../../scripts/setup/tls/rotate-server-cert.sh) — a thin wrapper around OpenSSL regeneration and secret deploy (not an AKO API):

| Order | Action | Effect |
|-------|--------|--------|
| 1 | Print current `svc_chain.pem` serial (if the file exists) | Baseline for comparison with Step 1 |
| 2 | [`generate-workshop-pki.sh --server-only`](../../scripts/setup/tls/generate-workshop-pki.sh) | Regenerates **only** `svc_chain.pem` / `svc_key.pem` under `secrets/tls/`; CA and client keys on disk unchanged |
| 3 | [`deploy-tls-secrets.sh`](../../scripts/setup/tls/deploy-tls-secrets.sh) | Idempotent `kubectl apply` of TLS secrets; **`tls-server-secret`** gets new data; same secret **names** and CR volume refs |

The script **does not** edit `AerospikeCluster` (see table above). It **does not** rotate client certs (`app.pem` stays the same on disk). After it finishes, allow ~60s for kubelet secret sync and Aerospike TLS file reload before verifying the pod mount.

`deploy-tls-secrets.sh` applies all workshop TLS secrets from disk; after `--server-only`, only server file content changed — client secret applies are effectively unchanged.

```text
rotate-server-cert.sh → generate-workshop-pki.sh --server-only → deploy-tls-secrets.sh
                              ↓                                        ↓
                    secrets/tls/svc_chain.pem (new serial)    tls-server-secret patched
                                                                        ↓
                                                              Aerospike hot-reloads mount
```

## Why access is preserved

During server cert rotation, clients and workloads stay authenticated because:

- **Client PKI certs are unchanged** — identity auth is unaffected.
- **Same workshop CA** — the new server cert is still signed by `cacert.pem`, which clients already trust.
- **Same TLS name and port** (`aerocluster:4333`) — no client reconfiguration.
- **No pod restart** — Aerospike reloads files on the existing mount; existing PKI connections and the background workload keep running. Confirm via unchanged container ID and steady TPS.

## Prerequisites

- Lab **3.3** complete (mTLS + PKI recommended)

## Node requirements

| Item | Value |
|------|-------|
| Instance | `i8g.2xlarge` baseline pool (same as Section 1) |
| Reset | **Skip** (default) — rotates server cert on live cluster; reuses node pools |
| Node pools | Unchanged from Labs 3.1–3.3 |

## Phase 0 — Prepare lab

**What:** Ensure PKI workload is running before rotating the server cert.
**Credential / mode:** Background asbench Job using client cert `app.pem` (`--pki`).
**Run:**

```bash
./scripts/labs/prepare-lab.sh 3.4 --skip-reset
./scripts/labs/run-lab-workload.sh --pki start
```

Watch TPS in a second terminal:

```bash
./scripts/labs/run-lab-workload.sh status
```

**Expect:** Steady TPS with no auth errors — baseline before rotation.

## Steps

### Step 1 — Record baseline (before rotation)

**What:** Capture server cert serial and pod container ID **before** any change.
**Credential / mode:** Server cert `svc_chain.pem` (serial A); client cert `app.pem` unchanged.
**Run:**

```bash
openssl x509 -in secrets/tls/svc_chain.pem -noout -dates -serial

POD=$(kubectl -n aerospike get pod -l aerospike.com/cr=aerocluster -o jsonpath='{.items[0].metadata.name}')
echo "Pod: ${POD}"
kubectl -n aerospike get pod "${POD}" -o jsonpath='Container ID: {.status.containerStatuses[?(@.name=="aerospike-server")].containerID}{"\n"}'
```

**Expect:** Note serial A and container ID — you will compare both after rotation.

### Step 2 — Rotate server certificate

**What:** Regenerate `svc_chain.pem` and patch `tls-server-secret` in place (same secret name). See [What the rotation scripts do](#what-the-rotation-scripts-do).
**Credential / mode:** Server cert only — client cert `app.pem` and CA unchanged.
**Run:**

```bash
./scripts/setup/tls/rotate-server-cert.sh
```

The script prints old and new server serials. **Expect:** Serial B differs from serial A; client certs unchanged.

Wait ~60s for secret sync to pods, then compare workstation file vs pod mount:

```bash
echo "Workstation serial:" && openssl x509 -in secrets/tls/svc_chain.pem -noout -serial

POD=$(kubectl -n aerospike get pod -l aerospike.com/cr=aerocluster -o jsonpath='{.items[0].metadata.name}')
echo "Pod-mounted serial:" && kubectl -n aerospike exec "${POD}" -c aerospike-server -- \
  openssl x509 -in /etc/aerospike/tls/svc_chain.pem -noout -serial
```

**Expect:** Workstation and pod-mounted serials match (serial B); both differ from serial A recorded in Step 1.

### Step 3 — Confirm no pod recreation

**What:** Verify the same pod process is still running (no AKO rolling restart).
**Credential / mode:** N/A — infrastructure check only.
**Run:**

```bash
kubectl -n aerospike get pod "${POD}" -o jsonpath='Container ID: {.status.containerStatuses[?(@.name=="aerospike-server")].containerID}{"\n"}'
```

**Expect:** Container ID unchanged from Step 1 — same pod, same process; only the cert file content changed.

## Verify

- Workload **TPS uninterrupted** (`run-lab-workload.sh status`)
- Pod **container ID unchanged** (no rolling restart for cert content update)
- Server serial B on pod mount matches workstation `svc_chain.pem`
- PKI clients still connect on **4333** (client cert `app.pem` unaffected)

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Clients fail after rotation | CA changed, wrong secret, or mount path changed — requires a CR change, not just a secret patch |
| Cert on pod still shows old dates after ~60s | Kubernetes secret sync delay — wait and re-check the mount inside the pod |
| Aerospike pods rolled after rotation | CR was changed (not just Secret data) — compare `AerospikeCluster` spec to pre-rotation state |

## Workshop artifacts

- [scripts/setup/tls/rotate-server-cert.sh](../../scripts/setup/tls/rotate-server-cert.sh) — regenerate + patch `tls-server-secret`
- [scripts/setup/tls/generate-workshop-pki.sh](../../scripts/setup/tls/generate-workshop-pki.sh) — use `--server-only` for OpenSSL server cert only
- [scripts/labs/run-lab-workload.sh](../../scripts/labs/run-lab-workload.sh) — background PKI workload (`--pki`)

## References

- [TLS certificate reload](https://aerospike.com/docs/server/operations/configure/network/tls/)
