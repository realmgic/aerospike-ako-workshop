# Workshop secrets

## features.conf (never commit)

Copy your Aerospike Enterprise **feature-key file** here as `features.conf`:

```bash
cp /path/to/your/features.conf secrets/features.conf
```

This file is gitignored. Each instructor must supply their own license from the Aerospike licensing portal.

## Lab auth passwords (committed defaults)

The following are **generic throwaway credentials** for disposable EKS lab clusters. They are applied by [`scripts/setup/07-deploy-secrets.sh`](../scripts/setup/07-deploy-secrets.sh) and documented in lab guides:

| Kubernetes secret | User | Password |
|-------------------|------|----------|
| `auth-secret` | admin | `admin123` |
| `auth-app-secret` | app | `app123` |
| `auth-exporter-secret` | exporter | `exporter123` |

These are safe to commit and share within the private workshop repo.
