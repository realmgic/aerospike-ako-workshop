# Lab 2.1 — akoctl: Install, Configuration, and Log Collection


| Field             | Value                                                          |
| ----------------- | -------------------------------------------------------------- |
| Lab ID            | `2.1`                                                          |
| Section           | Maintenance & Upgrade                                          |
| EKS cluster       | `my-cluster`                                                   |
| Deploy path       | both                                                           |
| Duration          | ~25 min                                                        |
| Validation status | `draft`                                                        |
| Official docs     | [akoctl](https://aerospike.com/docs/kubernetes/manage/akoctl/) |


## Takeaway

`akoctl` is the AKO Krew plugin for **RBAC setup** (`auth`) and **Kubernetes-side diagnostics** (`collectinfo`) — use global flags to target namespaces, kubeconfig, and cluster scope.

## Prerequisites

- Section 0 complete (akoctl installed in [Lab 0.4](../00-environment-setup/04-install-akoctl.md))
- After Section 1 labs, tear down the prior `aerocluster` CR and deploy the dim baseline (same cluster name):

```bash
./scripts/labs/prepare-lab.sh 2.1
```

**Expected:** Prior AerospikeCluster deleted; 3-node cluster `Running`; phase `Completed`.

Use `./scripts/labs/prepare-lab.sh 2.1 --skip-reset` only if the cluster is already deployed.

Manual deploy (if needed):

```bash
./scripts/labs/deploy-cluster.sh           # Path A (kubectl; default storage)
# or: ./scripts/labs/deploy-dim-cluster.sh       # explicit in-memory
# or: ./scripts/labs/deploy-cluster-helm.sh      # Path B (helm)
kubectl -n aerospike get pods
```



## Background


| Subcommand                    | Purpose                                                                              |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| `auth create` / `auth delete` | Create or remove RBAC for Aerospike cluster deploy in a namespace                    |
| `collectinfo`                 | Tar archive of K8s object YAML, events, container logs, CRDs, webhooks, node configs |


`collectinfo` is **Kubernetes-focused** — unlike `asadm collectinfo`, which captures OS/network detail from individual Aerospike nodes.

---



## Part 1 — Install and verify

If Section 0 was pre-staged, re-verify akoctl is available:

```bash
./scripts/setup/04-install-akoctl.sh
kubectl krew list | grep akoctl
kubectl akoctl --help
```

**Expected:** Help lists subcommands `auth` and `collectinfo`.

---



## Part 2 — Configuration (global flags)

Review global flags shared by all subcommands:

```bash
kubectl akoctl collectinfo --help
kubectl akoctl auth --help
```


| Flag               | Shorthand | Use                                               |
| ------------------ | --------- | ------------------------------------------------- |
| `--namespaces`     | `-n`      | Comma-separated namespaces (required unless `-A`) |
| `--all-namespaces` | `-A`      | Collect from all namespaces                       |
| `--kubeconfig`     |           | Non-default kubeconfig path                       |
| `--cluster-scope`  |           | Include cluster-scoped resources (default `true`) |


**Demo — explicit kubeconfig** (optional if using default context):

```bash
kubectl config current-context
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
kubectl akoctl auth create -n aerospike --kubeconfig "${KUBECONFIG}"
```

**Demo — namespace scope for auth** (discuss vs default cluster-scope):

```bash
# Default: cluster-scope=true (ClusterRoleBinding)
kubectl akoctl auth create -n aerospike

# Namespace-scoped RBAC only
kubectl akoctl auth delete -n aerospike
kubectl akoctl auth create -n aerospike --cluster-scope=false
kubectl get rolebinding,clusterrolebinding -n aerospike | grep aerospike
```

**Expected:** RoleBindings (and optionally ClusterRoleBindings) visible after `auth create`.

---



## Part 3 — Auth workflow

1. List existing bindings:
  ```bash
   kubectl get rolebinding,clusterrolebinding -A | grep aerospike
  ```
2. Recreate auth (idempotent demo):
  ```bash
   kubectl akoctl auth delete -n aerospike
   kubectl akoctl auth create -n aerospike
  ```
3. Confirm cluster deploy still works:
  ```bash
   kubectl -n aerospike get aerospikecluster aerocluster -o jsonpath='{.status.phase}'
  ```
   **Expected:** `Completed` (re-apply dim manifest if needed).

---



## Part 4 — Log collection (`collectinfo`)

Collect diagnostics from **Aerospike** and **operator** namespaces:

```bash
./scripts/labs/akoctl-collectinfo.sh
```

Or run manually with an absolute output path:

```bash
mkdir -p /tmp/akoctl-lab
kubectl akoctl collectinfo \
  -n aerospike,operators \
  --path /tmp/akoctl-lab
```

**Expected:** Command completes without error; tarball(s) appear under the output directory.

### What is collected

- Container and event logs
- AerospikeCluster CRs, pods, StatefulSets, PVCs, services
- Operator deployment logs in `operators`
- Cluster-scoped: nodes, StorageClasses, CRDs, admission webhooks (when `--cluster-scope=true`)



### Inspect output

```bash
ls -la /tmp/akoctl-lab
# Extract and browse (filename varies by timestamp)
tar -tzf /tmp/akoctl-lab/*.tar.gzip | head -30
```

**Discuss:** Use this bundle when opening Aerospike support cases — captures K8s state at a point in time.

### Compare with asadm (optional)

```bash
kubectl run -it --rm aerospike-tool -n aerospike --restart=Never \
  --image=aerospike/aerospike-tools:latest -- \
  asadm -h aerocluster -U admin -P admin123 -e "collectinfo"
```

**Point:** `asadm collectinfo` = database detail; `akoctl collectinfo` = cluster/operator/K8s detail.

---



## Verify (pass/fail)

1. `kubectl krew list | grep akoctl` — plugin installed
2. `kubectl akoctl auth create -n aerospike` — succeeds
3. `collectinfo` produces tarball under output path
4. Aerospike cluster phase `Completed`



## Troubleshooting


| Symptom                               | Fix                                                                                        |
| ------------------------------------- | ------------------------------------------------------------------------------------------ |
| Webhook / apply errors on dim cluster | Section 1 left a rack cluster with the same name — run `./scripts/labs/prepare-lab.sh 2.1` |
| `collectinfo` permission denied       | Ensure kubectl user can list/get pods, events, CRs in target namespaces                    |
| Empty or missing operator logs        | Include `operators` in `-n` list                                                           |
| `--path` error                        | Path must exist and be **absolute** — script creates it for you                            |
| auth create fails                     | Re-run `./scripts/setup/04-install-akoctl.sh`; check krew in PATH                          |




## Observe

- Tarball size grows with pod log volume
- Operator controller-manager logs included when `operators` namespace specified



## Not covered here

- asadm deep node diagnostics
- AKO upgrade → [Lab 2.2](02-upgrade-ako.md)



## Teardown / handoff

Leave cluster running for [Lab 2.2](02-upgrade-ako.md).

## References

- [akoctl](https://aerospike.com/docs/kubernetes/manage/akoctl/)
- [akoctl GitHub](https://github.com/aerospike/aerospike-kubernetes-operator-ctl)

