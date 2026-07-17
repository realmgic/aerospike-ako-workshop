# Lab 2.3 — Upgrade Aerospike DB

| Field | Value |
|-------|-------|
| Lab ID | `2.3` |
| Section | Maintenance & Upgrade |
| EKS cluster | `my-cluster` |
| AKO min version | `4.5.0` |
| Aerospike baseline | dim 3-node on **8.1.0.x** |
| Deploy path | both |
| Duration | ~20 min |
| Validation status | `draft` |
| Official docs | [Upgrade Aerospike](https://aerospike.com/docs/kubernetes/install/deploy/upgrade-aerospike/) |

## Takeaway

Aerospike DB upgrade = change `spec.image`; AKO performs a **rolling restart** of pods.

## Prerequisites

- Lab 2.2 complete (AKO **4.5.0+**)
- dim cluster Running on **8.1.0.x**

**Compatibility:** AKO 4.2.0–4.4.1 supports Aerospike up to **8.1.0.x** only. AKO **4.5.0** adds support for **8.1.2.x** — run this lab only after the 4.5.0 upgrade step in Lab 2.2.

## Phase 0 — Prepare lab

If you ran **[Lab 1.5](../01-scaling-and-capacity/05-replication-factor.md)**, the cluster may be at RF=3. If Lab 2.3 was attempted before, the image may already be on **8.1.2.x**. Reset to a clean dim baseline (**8.1.0.x**, RF=2) before upgrading:

```bash
./scripts/labs/teardown-cluster.sh
./scripts/labs/deploy-dim-cluster.sh       # Path A
# or
./scripts/labs/deploy-dim-cluster-helm.sh  # Path B
```

Confirm starting state:

```bash
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.spec.image}{"\n"}'
kubectl -n aerospike get pods
kubectl run -it --rm aerospike-tool-rf -n aerospike --restart=Never \
  --image=aerospike/aerospike-tools:latest -- \
  asadm -h aerocluster -U admin -P admin123 -e "show config like replication-factor"
```

**Pass:** Image `aerospike/aerospike-server-enterprise:8.1.0.0` (or current 8.1.0.x patch); 3/3 pods `Running`; all nodes report `replication-factor 2`.

## Steps

### Path A — kubectl

1. Record current image:

   ```bash
   kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.spec.image}'
   ```

   **Expected:** `aerospike/aerospike-server-enterprise:8.1.0.0` (or current 8.1.0.x patch).

2. Edit `manifests/aerospike-upgrade.yaml` — set image to **8.1.2.x** (e.g. `8.1.2.0`), apply:

   ```bash
   kubectl apply -f manifests/aerospike-upgrade.yaml
   kubectl -n aerospike get pods -w
   ```

   **Expected:** Sequential pod restarts; all `Running`.

### Path B — Helm

Update `image.tag` in `helm/aerospike-upgrade-values.yaml` to `8.1.2.0` and upgrade.

## Verify (pass/fail)

```bash
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.spec.image}'
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}'
```

**Pass:** Image tag on **8.1.2.x** line; phase `Completed`.

Optional:

```bash
kubectl exec -it aerocluster-0-0 -c aerospike-server -n aerospike -- asinfo -v build
```

## Observe

- One pod at a time restarted
- Cluster remains available during rolling upgrade

## Handoff

Proceed to [Lab 2.4](04-on-demand-operations.md).

## References

- [Upgrade Aerospike DB](https://aerospike.com/docs/kubernetes/install/deploy/upgrade-aerospike/)
