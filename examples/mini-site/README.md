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

## Upgrading to 0.21.0

Callers of `examples/mini-site/infra` pinned at `v0.20.x` must act on these
changes before moving the `?ref=` to `v0.21.0`. This is a migration, not a bump:

- **The Yandex Cloud hub is removed.** `yc.tf`, the `yandex` provider and the
  inputs `yc`, `yc_service_account_key_json`, `hub` and `hub_ingress_port_ranges`
  are gone; an unknown input is an error. **Callers whose hub runs on Yandex
  Cloud must stay on `v0.20.x`** until a YC hub returns. The hub and a test
  client are now Proxmox VE VMs (`bpg/proxmox`).
- **New required inputs:** `proxmox` (endpoint, node, pool, datastore, bridge,
  image, gateway, DNS, `hub` and `client` sizing), `ssh_public_key_file`,
  `ssh_private_key_file`, `known_hosts_file` (absolute), `k3s_version` and
  `cluster_cidrs`. **New optional inputs:** `api_trusted_cidrs`, `gcp_image`
  (default Ubuntu 26.04) and `routeros_enabled` (default `true`, so RouterOS
  callers see no change). The Proxmox API token comes from the
  `PROXMOX_VE_API_TOKEN` environment variable, not an input.
- **k3s comes from k3s-bootstrap (`v0.2.0`), not cloud-init.** The controller
  needs `uv`, `ssh-keyscan` and `flock`, and must export `ANSIBLE_SSH_ARGS` with
  `-o UserKnownHostsFile=<known_hosts_file>`; see [`infra/README.md`](infra/README.md).
  New edges default to Ubuntu 26.04, but an existing edge VM is **not**
  recreated: `modules/gcp_compute_host` ignores boot-image changes, so a 24.04
  edge keeps running its image and then fails the k3s-bootstrap v0.2.0
  preflight (`ansible_distribution_version == '26.04'`). To move such an edge
  to 26.04, check the plan, then replace it explicitly:
  `terragrunt apply -replace='module.gcp_edges["pt"].google_compute_instance.this'`
  (once per edge slug).
- **Output contract:** `connection_data_hub` and `connection_data_edges` carry
  `user = "garuda"` and the key **path** (`ssh_private_key_file`);
  `ssh_private_key` is always `null`. New output `connection_data_client`. The
  `routeros` output is `null` when `routeros_enabled = false`.
- **`required_version` is now `>= 1.9.0`.**
- **`modules/gcp_compute_host`:** new optional `ssh_public_key`; `instance_id`
  is now the numeric instance id (the former self-link is `instance_self_link`);
  `tls_private_key.admin` moves to `[0]` through a `moved` block, so state and
  the generated key are kept.
- `examples/mini-site/garuda` is unchanged.

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
