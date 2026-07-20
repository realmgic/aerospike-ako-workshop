# Lab 3.2 — TLS Only (Encryption in Transit)

| Field              | Value |
| ------------------ | ----- |
| Lab ID             | `3.2` |
| Section            | Security & Authentication |
| EKS cluster        | `my-cluster` |
| Aerospike cluster  | `aerocluster` |
| AKO min version    | `4.2.0` |
| Aerospike baseline | 3-node **8.1.0.0** with service TLS (standard auth, port **4333**) |
| Deploy path        | both |
| Duration           | ~20 min |
| Validation status  | `draft` |

## Takeaway

Encrypt client-to-cluster traffic with **server TLS only** (`tls-authenticate-client: false`). Clients still use **username/password** on port **4333**.

## Prerequisites

- Lab **3.1** (TLS secrets deployed)

## Node requirements

| Item | Value |
|------|-------|
| Instance | `i8g.2xlarge` baseline pool (same as Section 1) |
| Reset | None — continues from Lab 3.1 baseline cluster and TLS secrets |
| Node pools | Baseline pool from Lab 3.1 — no new nodegroups required |

## Phase 0 — Deploy TLS standard cluster

Lab **3.1** is the prep (PKI secrets + plain-TCP baseline). Upgrade in place to service TLS:

```bash
./scripts/labs/deploy-cluster-tls-standard.sh        # Path A
./scripts/labs/deploy-cluster-tls-standard-helm.sh   # Path B
```

This applies [`manifests/*-cluster-tls-standard.yaml`](../../manifests/disk-cluster-tls-standard.yaml) (server TLS on port **4333**; password auth unchanged). AKO requires `operatorClientCert` whenever service TLS is enabled — in this lab it reuses the **server cert** (`svc_chain.pem`, `tlsClientName: aerocluster`) for operator management TLS only. The `ako-operator` client cert is used from Lab **3.3** mTLS onward. App clients still use password only (no client cert).

## Steps

`aerocluster` is a headless Kubernetes Service (`ClusterIP: None`) — it only resolves inside the cluster network, not from your workstation. Run these `asadm`/`openssl` commands from a short-lived debug pod instead; `--rm --attach` prints output and cleans up the pod automatically.

### Connect with TLS + password (no client cert)

```bash
kubectl -n aerospike run aerospike-tool-tls --rm --attach --restart=Never \
  --image=aerospike/aerospike-tools:latest \
  --overrides='{"spec":{"containers":[{"name":"aerospike-tool-tls","image":"aerospike/aerospike-tools:latest",
    "command":["asadm"],
    "args":["-h","aerocluster:aerocluster:4333","--tls-enable","--tls-cafile","/etc/aerospike/tls/ca/cacert.pem","-U","admin","-P","admin123","-e","show stat like cluster_size"],
    "volumeMounts":[{"name":"tls-ca","mountPath":"/etc/aerospike/tls/ca","readOnly":true}]}],
    "volumes":[{"name":"tls-ca","secret":{"secretName":"tls-ca-secret"}}]}}'
```

### Confirm plain port still works

```bash
kubectl run -it --rm aerospike-tool -n aerospike --restart=Never \
  --image=aerospike/aerospike-tools:latest -- \
  asadm -h aerocluster -U admin -P admin123 -e "show stat like cluster_size"
```

### Inspect TLS handshake (no client cert required)

```bash
kubectl -n aerospike run aerospike-tls-inspect --rm --attach --restart=Never \
  --image=aerospike/aerospike-tools:latest \
  --overrides='{"spec":{"containers":[{"name":"aerospike-tls-inspect","image":"aerospike/aerospike-tools:latest",
    "command":["sh","-c","openssl s_client -connect aerocluster:4333 -CAfile /etc/aerospike/tls/ca/cacert.pem </dev/null"],
    "volumeMounts":[{"name":"tls-ca","mountPath":"/etc/aerospike/tls/ca","readOnly":true}]}],
    "volumes":[{"name":"tls-ca","secret":{"secretName":"tls-ca-secret"}}]}}'
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
