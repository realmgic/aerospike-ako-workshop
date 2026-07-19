# Lab 3.4 — Server Certificate Rotation

| Field              | Value |
| ------------------ | ----- |
| Lab ID             | `3.4` |
| Section            | Security & Authentication |
| AKO min version    | `4.2.0` |
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

- There is **no AKO “rotate certificate” API** — rotation is regenerate with OpenSSL, then `kubectl apply` the **same** Secret name.
- AKO’s role is **volume mount delivery** only. Hitless server rotation is **Aerospike TLS file reload** (see [References](#references)).
- **Contrast with Labs 3.2/3.3:** changing `network.tls[]`, `tls-authenticate-client`, or `authMode` is a **CR schema change** → AKO **rolling restart**. Lab 3.4 only changes **secret content** at the same mount path — no CR edit required.

## Why access is preserved

During server cert rotation, clients and workloads stay authenticated because:

- **Client PKI certs are unchanged** — identity auth is unaffected.
- **Same workshop CA** — the new server cert is still signed by `cacert.pem`, which clients already trust.
- **Same TLS name and port** (`aerocluster:4333`) — no client reconfiguration.
- **No pod restart** — Aerospike reloads files on the existing mount; existing PKI connections and the background workload keep running. Confirm via unchanged container ID and steady TPS.

## Prerequisites

- Lab **3.3** complete (mTLS + PKI recommended)

## Phase 0 — Prepare lab

```bash
./scripts/labs/prepare-lab.sh 3.4 --skip-reset
./scripts/labs/run-lab-workload.sh --pki start
```

Watch TPS in a second terminal:

```bash
./scripts/labs/run-lab-workload.sh status
```

## Steps

### Record current server cert

```bash
openssl x509 -in secrets/tls/svc_chain.pem -noout -dates -serial
```

### Rotate server certificate

```bash
./scripts/setup/tls/rotate-server-cert.sh
```

Wait ~60s for secret sync to pods, then verify new cert on a pod:

```bash
POD=$(kubectl -n aerospike get pod -l aerospike.com/cr=aerocluster -o jsonpath='{.items[0].metadata.name}')
kubectl -n aerospike exec "${POD}" -c aerospike -- \
  openssl x509 -in /etc/aerospike/tls/svc_chain.pem -noout -dates -serial
```

## Verify

- Workload **TPS uninterrupted** (`run-lab-workload.sh status`)
- Pod **container ID unchanged** (no rolling restart for cert content update)
- PKI clients still connect on **4333**

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Clients fail after rotation | CA changed, wrong secret, or mount path changed — requires a CR change, not just a secret patch |
| Cert on pod still shows old dates after ~60s | Kubernetes secret sync delay — wait and re-check the mount inside the pod |

## Workshop artifacts

| Script | Purpose |
|--------|---------|
| `scripts/setup/tls/rotate-server-cert.sh` | Regenerate + patch `tls-server-secret` |
| `scripts/setup/tls/generate-workshop-pki.sh --server-only` | OpenSSL server cert only |

## References

- [TLS certificate reload](https://aerospike.com/docs/server/operations/configure/network/tls/)
