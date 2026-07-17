# Lab 1.2 — Rack Awareness Basics


| Field              | Value                                                                                   |
| ------------------ | --------------------------------------------------------------------------------------- |
| Lab ID             | `1.2`                                                                                   |
| Section            | Scaling & Capacity                                                                      |
| EKS cluster        | `my-cluster`                                                                            |
| Aerospike cluster  | `aerocluster`                                                                           |
| AKO min version    | `4.2.0`                                                                                 |
| Aerospike baseline | dim cluster → add racks                                                                 |
| Deploy path        | both                                                                                    |
| Duration           | ~20 min                                                                                 |
| Validation status  | `draft`                                                                                 |
| Official docs      | [Rack awareness](https://aerospike.com/docs/kubernetes/manage/configure/rack-awareness) |




## Takeaway

Racks map to failure domains (zones); adding `rackConfig` redistributes pods and changes pod naming to include rack ID.

## Prerequisites

- Lab 1.1 complete, or run full prepare from scratch



## Node requirements


| Item       | Value                                                                      |
| ---------- | -------------------------------------------------------------------------- |
| Instance   | `i8g.2xlarge` × 4                                                          |
| Reset      | **Light** (database only; keeps nodes from 1.1; **scales baseline pool 5 → 4**) |
| Nodegroups | 2 × `${NODEGROUP_NAME}-<zone>` (eksctl) or 2 × `${KARPENTER_NODEPOOL_NAME}-<zone>` (Karpenter) |
| AZs        | ≥ `${MIN_NODES_PER_ZONE}` Ready per zone in `${AWS_ZONES}` (enforced by per-AZ pools at prepare) |




## Phase 0 — Prepare lab

```bash
./scripts/labs/prepare-lab.sh 1.2
```

If switching from Track B, run `./scripts/reset-cluster.sh --yes` then `./scripts/labs/prepare-lab.sh 1.2`.

**Expected:** 4× `i8g.2xlarge` Ready (2 per zone); multi-AZ validation passes.

## Background

Rack awareness aligns Aerospike replica placement with Kubernetes topology (e.g. AWS AZs). AKO schedules pods per rack and enables namespace-level rack configuration.

**Scheduling model:** Per-AZ workload pools pin nodes to each zone (`topology.kubernetes.io/zone`). AKO maps each rack ID to a zone via `rackConfig`; Track B also uses `podSpec.nodeSelector` (`workshop.aerospike.com/node-pool`) to pick baseline vs vertical instance pools.

## Steps



### Path A — kubectl

```bash
source scripts/env/workshop.env
./scripts/labs/deploy-dim-cluster-with-racks.sh
# or: envsubst '$NODE_ZONE_A $NODE_ZONE_B' < manifests/dim-cluster-with-racks.yaml | kubectl apply -f -
kubectl -n aerospike get pods -o wide
```

**Expected:** Pod names include rack ID (e.g. `aerocluster-1-0`, `aerocluster-2-0`).

### Path B — Helm

Render zones from `workshop.env`, then upgrade:

```bash
source scripts/env/workshop.env
# values: helm/dim-cluster-with-racks-values.yaml
envsubst '$NODE_ZONE_A $NODE_ZONE_B' < helm/dim-cluster-with-racks-values.yaml | \
  helm upgrade aerocluster aerospike/aerospike-cluster -n aerospike -f -
```

## Verify (pass/fail)

```bash
./scripts/labs/lab-nodes.sh 1.2 validate
kubectl -n aerospike get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
kubectl get nodes -L topology.kubernetes.io/zone
```

**Pass:** Pods spread across racks/zones; names reflect rack IDs.

Optional asadm check:

```bash
kubectl run -it --rm aerospike-tool -n aerospike --restart=Never \
  --image=aerospike/aerospike-tools:latest -- \
  asadm -h aerocluster -U admin -P admin123 -e "show config like rack-id"
```



## Observe

- Pod redistribution when racks added to existing cluster
- Namespace `test` listed under `rackConfig.namespaces`



## Not covered here

Rack revision/replacement → Labs [1.3](03-rack-revision.md), [1.4](04-rack-replacement.md)

## Troubleshooting


| Symptom                            | Fix                                                                                          |
| ---------------------------------- | -------------------------------------------------------------------------------------------- |
| `FailedScheduling`: node affinity  | `./scripts/reset-cluster.sh --yes && ./scripts/labs/prepare-lab.sh 1.2`                  |
| Pods stuck Pending                 | Confirm rendered `rackConfig` zones match `AWS_ZONES` in `workshop.env`                    |
| Multi-AZ validation fails at prepare | `./scripts/reset-cluster.sh --yes && ./scripts/labs/prepare-lab.sh 1.2`                  |

## Teardown / handoff

Track B: `./scripts/labs/prepare-lab.sh 1.3` (light reset — reuses baseline pool from 1.1/1.2).

Or `./scripts/reset-cluster.sh --yes` if done for the day.

## References

- [Rack awareness](https://aerospike.com/docs/kubernetes/manage/configure/rack-awareness)

