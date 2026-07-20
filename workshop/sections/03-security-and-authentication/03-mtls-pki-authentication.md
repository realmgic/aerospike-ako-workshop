# Lab 3.3 — mTLS and PKI Authentication

| Field              | Value |
| ------------------ | ----- |
| Lab ID             | `3.3` |
| Section            | Security & Authentication |
| AKO min version    | `4.2.0` |
| Duration           | ~30 min |
| Validation status  | `draft` |

## Takeaway

Escalate service TLS to **mTLS** (client cert required), then migrate from password auth to **PKI** and finally **`PKIOnly`**.

## Prerequisites

- Lab **3.2** (cluster on standard-auth TLS)

## Phase 0 — Prepare lab

```bash
./scripts/labs/prepare-lab.sh 3.3 --skip-reset
```

Or deploy mTLS manifest:

```bash
./scripts/labs/deploy-cluster-tls-mtls.sh
./scripts/labs/deploy-cluster-tls-mtls-helm.sh   # Path B
```

### Deploy note — schema change vs cert content

Changes in this lab to `network.tls[]`, `tls-authenticate-client`, or `authMode: PKIOnly` are **CR schema changes** → AKO performs a **rolling restart** of Aerospike pods.

Later labs (**3.4** and **3.5**) rotate **certificate file content** or revoke by serial number — a different mechanism, mostly **hitless at the Aerospike layer** (server file reload and PKI overlap/blacklist). Keep this distinction in mind when comparing rolling restarts here to uninterrupted workload in Lab 3.4.

## Phase A — mTLS + password

Connect with client cert **and** password:

```bash
asadm -h "aerocluster:aerocluster:4333" --tls-enable \
  --tls-cafile secrets/tls/cacert.pem \
  --tls-certfile secrets/tls/app.pem --tls-keyfile secrets/tls/app.key \
  -U app -P app123 -e "info"
```

**Expected:** Lab 3.2 connection without client cert now **fails**.

## Phase B — PKI auth (no password)

```bash
asadm -h "aerocluster:aerocluster:4333" --tls-enable \
  --tls-cafile secrets/tls/cacert.pem \
  --tls-certfile secrets/tls/app.pem --tls-keyfile secrets/tls/app.key \
  --auth PKI -e "info"
```

Workload example:

```bash
./scripts/labs/run-lab-workload.sh --pki start
./scripts/labs/load-data.sh --pki
```

## Phase C — PKIOnly

Apply PKIOnly manifest (migrate **`app`** and **`exporter`** first, **`admin`** last):

```bash
./scripts/labs/deploy-cluster-tls-mtls-pki-only.sh
# Path B: ./scripts/labs/deploy-cluster-tls-mtls-pki-only-helm.sh
```

Confirm PKI login for `admin` in a **second terminal** before applying — `PKIOnly` is **one-way**.

**Verify:** Password login fails for migrated users; PKI login succeeds; exporter sidecar scrapes metrics on `:9145`.

## Verify

| Phase | Pass criteria |
|-------|---------------|
| A | Client cert required; password still works |
| B | `--auth PKI` succeeds without `-P` |
| C | Password rejected; PKI works; exporter healthy |

## Workshop artifacts

Workshop YAML used in this lab (Path A = `kubectl apply`; Path B = `helm upgrade -f`):

- **mTLS (Phase A/B):**
  - Path A: [manifests/disk-cluster-tls-mtls.yaml](../../manifests/disk-cluster-tls-mtls.yaml) (default) · [manifests/dim-cluster-tls-mtls.yaml](../../manifests/dim-cluster-tls-mtls.yaml) (`--dim`)
  - Path B: [helm/disk-cluster-tls-mtls-values.yaml](../../helm/disk-cluster-tls-mtls-values.yaml) · [helm/dim-cluster-tls-mtls-values.yaml](../../helm/dim-cluster-tls-mtls-values.yaml)
- **PKIOnly (Phase C):**
  - Path A: [manifests/disk-cluster-tls-mtls-pki-only.yaml](../../manifests/disk-cluster-tls-mtls-pki-only.yaml) (default) · [manifests/dim-cluster-tls-mtls-pki-only.yaml](../../manifests/dim-cluster-tls-mtls-pki-only.yaml) (`--dim`)
  - Path B: [helm/disk-cluster-tls-mtls-pki-only-values.yaml](../../helm/disk-cluster-tls-mtls-pki-only-values.yaml) · [helm/dim-cluster-tls-mtls-pki-only-values.yaml](../../helm/dim-cluster-tls-mtls-pki-only-values.yaml)
- Deploy scripts: [scripts/labs/deploy-cluster-tls-mtls.sh](../../scripts/labs/deploy-cluster-tls-mtls.sh) · [scripts/labs/deploy-cluster-tls-mtls-helm.sh](../../scripts/labs/deploy-cluster-tls-mtls-helm.sh) · [scripts/labs/deploy-cluster-tls-mtls-pki-only.sh](../../scripts/labs/deploy-cluster-tls-mtls-pki-only.sh) · [scripts/labs/deploy-cluster-tls-mtls-pki-only-helm.sh](../../scripts/labs/deploy-cluster-tls-mtls-pki-only-helm.sh)
- Workload: [scripts/labs/run-lab-workload.sh](../../scripts/labs/run-lab-workload.sh) · [scripts/labs/load-data.sh](../../scripts/labs/load-data.sh)

## References

- [PKI authentication](https://aerospike.com/docs/server/operations/configure/security/pki/)
- [Prometheus exporter PKI](https://aerospike.com/docs/tools/monitorstack/)
