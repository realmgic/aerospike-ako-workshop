# Lab 2.4 — Upgrade Aerospike DB

| Field | Value |
|-------|-------|
| Lab ID | `2.4` |
| Section | Maintenance & Upgrade |
| EKS cluster | `my-cluster` |
| AKO min version | `4.5.0` |
| Aerospike baseline | 3-node on **8.1.0.x** (device storage default) |
| Deploy path | both |
| Duration | ~20 min |
| Validation status | `draft` |
| Official docs | [Upgrade Aerospike](https://aerospike.com/docs/kubernetes/install/deploy/upgrade-aerospike/) |

## Takeaway

Aerospike DB upgrade = change `spec.image`; AKO performs a **rolling restart** of pods.

## Prerequisites

- Lab 2.3 complete (on-demand operations on **8.1.0.x**)
- Lab 2.2 complete (AKO **4.5.0+**)
- cluster Running on **8.1.0.x**

**Compatibility:** AKO 4.2.0–4.4.1 supports Aerospike up to **8.1.0.x** only. AKO **4.5.0** adds support for **8.1.2.x** — run this lab only after the 4.5.0 upgrade step in Lab 2.2.

## Phase 0 — Prepare lab

After **Lab 2.3**, the CR may still carry `spec.operations`. AKO cannot apply an image change together with an operations change — reset to a clean baseline before upgrading:

If you ran **[Lab 1.4](../01-scaling-and-capacity/04-replication-factor.md)**, the cluster may be at RF=3. If Lab 2.4 was attempted before, the image may already be on **8.1.2.x**. Reset to a clean baseline (**8.1.0.x**, RF=2, no operations):

```bash
./scripts/labs/prepare-lab.sh 2.4
```

**Expected:** Prior `aerocluster` deleted; fresh 3-node cluster on **8.1.0.x**; phase `Completed`.

Use `./scripts/labs/prepare-lab.sh 2.4 --skip-reset` only if the baseline is already on **8.1.0.x** and Running.

Confirm starting state:

```bash
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.spec.image}{"\n"}'
kubectl -n aerospike get pods
kubectl run -it --rm aerospike-tool-rf -n aerospike --restart=Never \
  --image=aerospike/aerospike-tools:latest -- \
  asadm -h aerocluster -U admin -P admin123 -e "show config like replication-factor"
```

**Pass:** Image `aerospike/aerospike-server-enterprise:8.1.0.0` (or current 8.1.0.x patch); 3/3 pods `Running`; all nodes report `replication-factor 2`.

## Optional — continuous workload (Terminal B)

Open a **second terminal window**. If the cluster has no records yet, load data first with `./scripts/labs/load-data.sh` in Terminal A, then start throughput:

```bash
./scripts/labs/run-lab-workload.sh start
```

Watch TPS in Terminal B (`status` tails `--debug` output). Perform the upgrade steps below in Terminal A. When finished:

```bash
./scripts/labs/run-lab-workload.sh stop
```

## Steps

### Path A — kubectl

1. Record current image:

   ```bash
   kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.spec.image}'
   ```

   **Expected:** `aerospike/aerospike-server-enterprise:8.1.0.0` (or current 8.1.0.x patch).

2. Edit `manifests/disk-aerospike-upgrade.yaml` (or `manifests/aerospike-upgrade.yaml` with `--dim`) — set image to **8.1.2.x** (e.g. `8.1.2.0`), apply:

   ```bash
   kubectl apply -f manifests/disk-aerospike-upgrade.yaml
   kubectl -n aerospike get pods -w
   ```

   **Expected:** Sequential pod restarts; all `Running`.

### Path B — Helm

Update `image.tag` in `helm/disk-aerospike-upgrade-values.yaml` (or `helm/aerospike-upgrade-values.yaml` with `--dim`) to `8.1.2.0` and upgrade.

## Verify (pass/fail)

```bash
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.spec.image}'
kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}'
```

**Pass:** Image tag on **8.1.2.x** line; phase `Completed`.

Optional:

```bash
kubectl exec -it aerocluster-0-0 -c aerospike-server -n aerospike -- asinfo -U admin -P admin123 -v build
```

## Observe

- One pod at a time restarted
- Cluster remains available during rolling upgrade

## Handoff

Proceed to [Lab 2.5](05-k8s-node-maintenance.md).

## References

- [Upgrade Aerospike DB](https://aerospike.com/docs/kubernetes/install/deploy/upgrade-aerospike/)
- [scripts/labs/run-lab-workload.sh](../../scripts/labs/run-lab-workload.sh)
