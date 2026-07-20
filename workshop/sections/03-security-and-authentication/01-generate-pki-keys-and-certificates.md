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

## Node requirements

| Item | Value |
|------|-------|
| Instance | `i8g.2xlarge` baseline pool (same as Section 1) |
| Reset | **Light** — reuses existing node pools; does **not** tear down nodegroups/NodePools |
| Node pools | Baseline pool must exist — `prepare-lab.sh` runs `lab-nodes.sh 1.1 ensure` |

If you ran Section 1 or 2 earlier, workload nodes are reused as-is. You do **not** need `--full` for Lab 3.1.

## Phase 0 — Prepare lab

Light reset redeploys a plain-TCP **8.1.0.0** cluster and validates the baseline node pool (clears Section 2 CR drift without removing nodes):

```bash
./scripts/labs/prepare-lab.sh 3.1
```

**Expected:** baseline node pool Ready; 3-node plain-TCP cluster on **8.1.0.0**; no TLS on port 4333 yet.

## Steps

### Generate PKI material

```bash
./scripts/setup/tls/generate-workshop-pki.sh
```

Output under `secrets/tls/` (gitignored): `cacert.pem`, `svc_chain.pem`, `svc_key.pem`, client certs for `admin`, `app`, `exporter`, `operator_client` (CN=`aerocluster`, AKO Lab 3.2), `ako-operator`.

The server cert (`svc_chain.pem`) is signed with **`subjectAltName = DNS:aerocluster`**, not just `CN=aerocluster`. This matters because the AKO operator's embedded Aerospike client is written in Go, and Go's `crypto/x509` has ignored the legacy CN-as-hostname fallback since Go 1.15 — a CN-only server cert fails hostname verification during the operator's TLS handshake with `tls-name: aerocluster` and blocks ACL reconcile in Lab 3.2. If you ever regenerate the server cert manually (outside this script), keep the SAN.

### Deploy Kubernetes secrets

```bash
./scripts/setup/tls/deploy-tls-secrets.sh
```

**Expected secrets:** `tls-ca-secret`, `tls-server-secret`, `tls-client-*-secret`, `tls-ako-client-secret`.

## Verify

```bash
kubectl -n aerospike get secret tls-ca-secret tls-server-secret tls-client-app-secret
openssl x509 -in secrets/tls/app.pem -noout -subject   # CN=app

kubectl run -it --rm aerospike-tool -n aerospike --restart=Never \
  --image=aerospike/aerospike-tools:latest -- \
  asadm -h aerocluster -U admin -P admin123 -e "show stat like cluster_size"
```

**Expected:** `cluster_size` **3** (plain TCP on port 3000 — TLS not enabled on the cluster yet).

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `openssl: command not found` | Install OpenSSL on workstation |
| Secrets missing in cluster | Re-run `deploy-tls-secrets.sh`; verify kubectl context |
| Lab 3.2 stuck in `phase=Error` / `ACLUpdateFailed`, server logs show `SSL alert bad certificate` | Server cert missing a SAN — check `openssl x509 -in secrets/tls/svc_chain.pem -noout -text \| grep -A1 "Subject Alternative Name"`; if absent, re-run `generate-workshop-pki.sh --server-only` + `deploy-tls-secrets.sh` |

## Handoff

Secrets are ready for Lab **3.2**. Client cert secrets are **not** consumed by the cluster until Lab **3.3**. Lab **3.2** starts by deploying the TLS standard cluster (`deploy-cluster-tls-standard.sh` or `-helm.sh`) — no separate `prepare-lab.sh 3.2`.

## Workshop artifacts

- [scripts/setup/tls/generate-workshop-pki.sh](../../scripts/setup/tls/generate-workshop-pki.sh) — OpenSSL CA + certs
- [scripts/setup/tls/deploy-tls-secrets.sh](../../scripts/setup/tls/deploy-tls-secrets.sh) — kubectl apply secrets
- [secrets/README.md](../../secrets/README.md) — TLS secret layout; generated files under `secrets/tls/` (gitignored)

## References

- [Aerospike TLS](https://aerospike.com/docs/server/operations/configure/network/tls/)
- [PKI authentication](https://aerospike.com/docs/server/operations/configure/security/pki/)
