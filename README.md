# Aerospike AKO Workshop

Private instructor-led workshop materials for the **Aerospike Kubernetes Operator (AKO)** on AWS EKS.

## Quick start

```bash
git clone git@github.com:<org>/aerospike-ako-workshop.git
cd aerospike-ako-workshop/workshop
cp scripts/env/workshop.env.example scripts/env/workshop.env
cp /path/to/your/features.conf secrets/features.conf   # license — not in repo
./scripts/setup/01-validate-client.sh
```

Full walkthrough guide: [workshop/README.md](workshop/README.md)

## Prerequisites

- AWS account with EKS permissions
- Aerospike Enterprise `features.conf` (from licensing portal)
- Tools listed in [workshop/instructor/client-prerequisites.md](workshop/instructor/client-prerequisites.md)

## Repository layout

```text
aerospike-ako-workshop/
├── README.md          # this file
└── workshop/          # all lab guides, manifests, scripts
```

Everything needed to run the workshop lives under `workshop/`.
