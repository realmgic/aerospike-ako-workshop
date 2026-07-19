#!/usr/bin/env python3
"""Generate Helm values from AerospikeCluster manifest YAML (workshop helper)."""
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML required: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def manifest_to_helm(manifest_path: Path) -> str:
    data = yaml.safe_load(manifest_path.read_text())
    spec = data["spec"]
    image = spec["image"]
    repo, tag = image.rsplit(":", 1)
    out = {
        "replicas": spec["size"],
        "enableDynamicConfigUpdate": spec.get("enableDynamicConfigUpdate", True),
        "image": {"repository": repo, "tag": tag},
    }
    for key in (
        "operatorClientCert",
        "podSpec",
        "storage",
        "aerospikeAccessControl",
        "aerospikeConfig",
    ):
        if key in spec:
            out[key] = spec[key]
    header = f"# Mirrors {manifest_path.name}\n"
    return header + yaml.dump(out, default_flow_style=False, sort_keys=False)


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    pairs = [
        ("manifests/disk-cluster-tls-standard.yaml", "helm/disk-cluster-tls-standard-values.yaml"),
        ("manifests/dim-cluster-tls-standard.yaml", "helm/dim-cluster-tls-standard-values.yaml"),
        ("manifests/disk-cluster-tls-mtls.yaml", "helm/disk-cluster-tls-mtls-values.yaml"),
        ("manifests/dim-cluster-tls-mtls.yaml", "helm/dim-cluster-tls-mtls-values.yaml"),
        ("manifests/disk-cluster-tls-mtls-pki-only.yaml", "helm/disk-cluster-tls-mtls-pki-only-values.yaml"),
        ("manifests/dim-cluster-tls-mtls-pki-only.yaml", "helm/dim-cluster-tls-mtls-pki-only-values.yaml"),
        ("manifests/disk-cluster-tls-mtls-blacklist.yaml", "helm/disk-cluster-tls-mtls-blacklist-values.yaml"),
        ("manifests/dim-cluster-tls-mtls-blacklist.yaml", "helm/dim-cluster-tls-mtls-blacklist-values.yaml"),
    ]
    for src, dst in pairs:
        src_path = root / src
        dst_path = root / dst
        dst_path.write_text(manifest_to_helm(src_path))
        print(f"Wrote {dst_path.relative_to(root)}")


if __name__ == "__main__":
    main()
