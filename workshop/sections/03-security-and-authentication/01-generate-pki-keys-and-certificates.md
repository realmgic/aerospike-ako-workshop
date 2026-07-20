# Lab 3.1 — Generate PKI Keys and Certificates

| Field              | Value |
| ------------------ | ----- |
| Lab ID             | `3.1` |
| Section            | Security & Authentication |
| EKS cluster        | `my-cluster` |
| Aerospike cluster  | `aerocluster` |
| AKO min version    | `4.2.0` |
| Aerospike baseline | 3-node **8.1.0.0** (plain TCP until Lab 3.2) |
| Deploy path        | both |
| Duration           | ~20 min |
| Validation status  | `draft` |

## Takeaway

Build workshop PKI **before** enabling TLS on the cluster: CA, server cert (`CN=aerocluster`), client certs (`CN` = username).

## Prerequisites

- Lab **0.6** complete (auth secrets deployed)
- `openssl` on your workstation

## Phase 0 — Prepare lab

Always uses a **full reset** (clears Section 2 CR drift):

```bash
./scripts/labs/prepare-lab.sh 3.1 --full
```

**Expected:** 3-node plain-TCP cluster on **8.1.0.0**; no TLS on port 3000 yet.

## Steps

### Generate PKI material

```bash
./scripts/setup/tls/generate-workshop-pki.sh
```

Output under `secrets/tls/` (gitignored): `cacert.pem`, `svc_chain.pem`, `svc_key.pem`, client certs for `admin`, `app`, `exporter`, `ako-operator`.

### Deploy Kubernetes secrets

```bash
./scripts/setup/tls/deploy-tls-secrets.sh
```

**Expected secrets:** `tls-ca-secret`, `tls-server-secret`, `tls-client-*-secret`, `tls-ako-client-secret`.

## Verify

```bash
kubectl -n aerospike get secret tls-ca-secret tls-server-secret tls-client-app-secret
openssl x509 -in secrets/tls/app.pem -noout -subject   # CN=app
asadm -h aerocluster -U admin -P admin123 -e "show stat like cluster_size"   # still plain TCP
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `openssl: command not found` | Install OpenSSL on workstation |
| Secrets missing in cluster | Re-run `deploy-tls-secrets.sh`; verify kubectl context |

## Handoff

Secrets are ready for Lab **3.2**. Client cert secrets are **not** consumed by the cluster until Lab **3.3**.

## Workshop artifacts

- [scripts/setup/tls/generate-workshop-pki.sh](../../scripts/setup/tls/generate-workshop-pki.sh) — OpenSSL CA + certs
- [scripts/setup/tls/deploy-tls-secrets.sh](../../scripts/setup/tls/deploy-tls-secrets.sh) — kubectl apply secrets
- [secrets/README.md](../../secrets/README.md) — TLS secret layout; generated files under `secrets/tls/` (gitignored)

## References

- [Aerospike TLS](https://aerospike.com/docs/server/operations/configure/network/tls/)
- [PKI authentication](https://aerospike.com/docs/server/operations/configure/security/pki/)
