# Section 03 — Security & Authentication

## Section takeaway

Encrypt client traffic with Aerospike **service TLS**, then escalate to **mTLS** and **PKI authentication**, and practice live certificate rotation without downtime.

## Labs in this section

| Lab | Title | Duration | Depends on |
|-----|-------|----------|------------|
| 3.1 | Generate PKI keys and certificates | ~20 min | 0.6 |
| 3.2 | TLS only (encryption in transit) | ~20 min | 3.1 |
| 3.3 | mTLS and PKI authentication | ~30 min | 3.2 |
| 3.4 | Server certificate rotation | ~20 min | 3.3 |
| 3.5 | Live client credential rotation | ~25 min | 3.4 |

See [LAB_REGISTRY.yaml](../../LAB_REGISTRY.yaml) for machine-readable metadata.

## Recommended order

```text
3.1 → 3.2 → 3.3 → 3.4 → 3.5
```

Section 3 is **optional** and independent of Section 2 — only Lab **0.6** is required. In a full workshop, teach Section 3 **after Lab 2.5** (core Section 2 complete). Lab **2.6** is optional and may precede or follow Section 3.

## Scope

- **In scope:** `network.service` TLS on port **4333** (`tls-name: aerocluster`); fabric **3001**, heartbeat **3002**, admin **3003** stay plain TCP.
- **Out of scope:** K8s platform TLS (webhooks, cert-manager), fabric/heartbeat TLS, external secret managers.

## Deploy path

Pick **Path A (kubectl/OLM)** or **Path B (Helm)** in Section 0 and stay consistent. TLS manifests mirror the baseline cluster (`exporter` **1.33.0**, Aerospike **8.1.0.0**).

## How to read commands

Each lab labels command blocks with three lines:

- **What:** what the step does
- **Credential / mode:** which cert, auth mode, or port is in use (e.g. plain TCP, TLS+password, PKI, client cert v1 vs v2)
- **Expect:** what success looks like in the output

Wrapper scripts (`rotate-server-cert.sh`, `rotate-client-cert.sh`, `apply-cert-blacklist.sh`, etc.) echo key facts to stdout when you run them. Labs **3.4** and **3.5** also document each wrapper under **Background** (*What the rotation scripts do*; Lab 3.5 adds *What Step 4 does*) — read those before the step commands.

## Instructor notes

See [instructor-notes.md](instructor-notes.md) for timing, PKIOnly migration order, and skip paths.
