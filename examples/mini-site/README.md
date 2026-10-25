# Mini-Site Reference Example

This directory is the public sanitized reference topology for Garuda. It contains
a template that operators can copy and adapt — not production credentials or real
cloud IDs.

The directory currently contains documentation and sanitized inputs only. Add the
Terragrunt/OpenTofu files for your environment before running the commands below.

## Units

Deploy in order:

1. **`infra/`** — Provisions compute, DNS, and RouterOS bootstrap resources.
   Exports: `connection_data_hub`, `connection_data_edges`, `cloudflare_hub`,
   `cloudflare_edges`, `routeros`.

2. **`garuda/`** — Consumes `infra/` outputs and deploys hub workloads, edge
   WireGuard tunnels, RouterOS tunnel, Firezone, and `ipt_server`.

## Quick start

```bash
cd examples/mini-site/infra
terragrunt apply

cd ../garuda
terragrunt apply
terragrunt plan -detailed-exitcode   # 0 = the apply left no drift
```

End-to-end tests live in the local stand only:
[`../local-stand/e2e/README.md`](../local-stand/e2e/README.md).

## Upgrading to 0.20.0

Callers of `examples/mini-site/garuda` pinned at `v0.19.x` must act on these
removals before moving the `?ref=` to `v0.20.0`:

- **Variable `smoke_client_firezone` is removed.** Stop passing it; an unknown
  input is an error. The Firezone test client now lives in the local stand
  (`examples/local-stand`).
- **Outputs `ansible_smoke_inventory` and `ansible_client_inventory` are
  removed.** Drop any dependency or consumer that reads them.
- **`keys.tf` and the `hashicorp/local` provider requirement are removed.** The
  first apply after the upgrade destroys three `local_sensitive_file` resources
  (the hub key and one key per edge, under `.keys/`). This is a one-time,
  expected plan; nothing on the hosts changes.
- **`examples/mini-site/smoke/` (the z2g Ansible smoke) is removed.** End-to-end
  tests now run on the local stand: [`../local-stand/e2e/README.md`](../local-stand/e2e/README.md).

Additions are opt-in and default to the previous behaviour: `routeros_enabled`,
`remnawave_enabled`, `firezone_oidc_enabled`, `ipt_route_groups`, the
`cert_manager_*` RFC 2136 solver inputs, `pod_reaper_max_unready`, and the
`mtu_policy` output.

## Adapting for real deployments

1. Copy `inputs.tfvars.yaml.example` to `inputs.tfvars.yaml` (or your SOPS-encrypted
   equivalent) and replace every placeholder value.
2. Replace `example.net` with your actual base domain.
3. Replace RFC 5737 CIDRs (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`)
   with your actual WireGuard address ranges.
4. Add real cloud provider credentials and SSH keys.

Do not commit real secrets to version control.

## Further reading

- [Reference topology walkthrough](../../docs/getting-started/reference-topology.md)
- [First deploy guide](../../docs/getting-started/first-deploy.md)
- [Module index](../../docs/reference/modules.md)
