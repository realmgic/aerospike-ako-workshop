# Lab 3.2 — TLS Only (Encryption in Transit)

| Field              | Value |
| ------------------ | ----- |
| Lab ID             | `3.2` |
| Section            | Security & Authentication |
| AKO min version    | `4.2.0` |
| Duration           | ~20 min |
| Validation status  | `draft` |

## Takeaway

Encrypt client-to-cluster traffic with **server TLS only** (`tls-authenticate-client: false`). Clients still use **username/password** on port **4333**.

## Prerequisites

- Lab **3.1** (TLS secrets deployed)

## Phase 0 — Prepare lab

```bash
./scripts/labs/prepare-lab.sh 3.2
```

Deploys the standard-auth TLS cluster (`manifests/*-cluster-tls-standard.yaml`).

Or deploy manually:

```bash
./scripts/labs/deploy-cluster-tls-standard.sh        # Path A
./scripts/labs/deploy-cluster-tls-standard-helm.sh   # Path B
```

## Steps

### Connect with TLS + password (no client cert)

```bash
asadm -h "aerocluster:aerocluster:4333" --tls-enable \
  --tls-cafile secrets/tls/cacert.pem \
  -U admin -P admin123 -e "show stat like cluster_size"
```

### Confirm plain port still works

```bash
asadm -h aerocluster -U admin -P admin123 -e "show stat like cluster_size"
```

### Inspect TLS handshake (no client cert required)

```bash
POD_IP=$(kubectl -n aerospike get pod -l aerospike.com/cr=aerocluster -o jsonpath='{.items[0].status.podIP}')
openssl s_client -connect "${POD_IP}:4333" -CAfile secrets/tls/cacert.pem </dev/null
```

## Verify (pass/fail)

- TLS on **4333** succeeds with `--tls-cafile` only
- Omitting `-U`/`-P` fails (password still required)
- Plain port **3000** still reachable

## Handoff

Leave the cluster on standard-auth TLS. Lab **3.3** escalates to mTLS (`tls-authenticate-client: any`).

## Workshop artifacts

Workshop YAML used in this lab (Path A = `kubectl apply`; Path B = `helm upgrade -f`):

- **TLS standard auth (server cert only):**
  - Path A: [manifests/disk-cluster-tls-standard.yaml](../../manifests/disk-cluster-tls-standard.yaml) (default) · [manifests/dim-cluster-tls-standard.yaml](../../manifests/dim-cluster-tls-standard.yaml) (`--dim`)
  - Path B: [helm/disk-cluster-tls-standard-values.yaml](../../helm/disk-cluster-tls-standard-values.yaml) · [helm/dim-cluster-tls-standard-values.yaml](../../helm/dim-cluster-tls-standard-values.yaml)
- Deploy scripts: [scripts/labs/deploy-cluster-tls-standard.sh](../../scripts/labs/deploy-cluster-tls-standard.sh) · [scripts/labs/deploy-cluster-tls-standard-helm.sh](../../scripts/labs/deploy-cluster-tls-standard-helm.sh)

## References

- [AKO TLS configuration](https://aerospike.com/docs/kubernetes/manage/configure/network/tls/)
