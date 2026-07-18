# Client Prerequisites Checklist

Print and check before class.

## Tools

- [ ] `aws sts get-caller-identity` succeeds
- [ ] `kubectl version --client`
- [ ] `eksctl version`
- [ ] `git --version`
- [ ] `curl --version`
- [ ] `kubectl krew version`
- [ ] Helm (Path B only): `helm version`
- [ ] jq (optional)
- [ ] akoctl (optional — installed in Lab 0.4)
- [ ] `local_volume_provisioner_cleanup*.yaml` at repo root

## AWS

- [ ] Region: `us-east-1` (or configured in workshop.env)
- [ ] EC2 key pair exists
- [ ] Quota for main cluster (4× i8g.2xlarge baseline)
- [ ] Quota for Lab 1.2 vertical scale (4× i8g.4xlarge)
- [ ] Quota for upgrade-lab (3× i8g.2xlarge)

## Files

- [ ] `secrets/features.conf` present
- [ ] `workshop/scripts/env/workshop.env` configured
- [ ] Operator repo cloned (or will clone on setup)

## Validation script

```bash
cd workshop && ./scripts/setup/01-validate-client.sh
```

- [ ] Exit code 0

## Sign-off

| Field | Value |
|-------|-------|
| Instructor | |
| Date | |
