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

## Upgrading to 0.24.0

`examples/mini-site/garuda` moves Firezone to v3 on a CNPG database. This is a
data migration, not just a ref bump:

- **Migrate the v2 database before the upgrade apply.** Firezone v3 starts on
  an empty `firezone` database unless the old one is dumped and restored
  first. Follow the [CNPG migration runbook](https://github.com/garuda-tunnel/firezone/blob/main/docs/operations/operator-runbook-cnpg-migration.md)
  in the firezone repository, including its kernel/AppArmor precondition.
- The v2 hostPath `postgres-data` directory is neither mounted nor deleted by
  v3; remove it manually only after the migration has soaked.
- Durability of the new database (data disk placement, re-attach after a VM rebuild) is an
  operator duty: see
  [`garuda/README.md`](garuda/README.md) → "Operator prerequisites".

## Upgrading: caller-owned GCP addresses

This upgrade requires OpenTofu 1.10.0 or newer.

GCP edges now require caller-owned regional external addresses, declared in
the example as `google_compute_address.edge` with `prevent_destroy`. **Before
applying**, move each existing module-owned address in state, once per edge
key (list them with `terragrunt state list | grep google_compute_address.this`):

```bash
terragrunt state mv \
  'module.gcp_edges["<key>"].google_compute_address.this[0]' \
  'google_compute_address.edge["<key>"]'
```

Check the plan shows no change to any `google_compute_address`. **Do not
apply if the plan shows `forget` for a `google_compute_address`**: a missed
move removes the legacy address from state and plans a new address of the
same name, which fails at apply (the name exists) and leaves the old IP
unmanaged until imported. Run the missing `state mv` and re-plan. If an
edge previously had no static address, it needs a new or imported address. See
the [module migration instructions](../../modules/gcp_compute_host/README.md).

To keep, release or remove these addresses later, see
[GCP edge addresses](../../docs/operations/deploy-update-destroy.md#gcp-edge-addresses).

## Site MTU/MSS policy (`mtu_policy`)

`local.mtu_policy` in `garuda/main.tf` (`{ site_mtu = 1330 }`) is the one site-level MTU/MSS
setting. Every component module takes the same `mtu_policy` object (`site_mtu`, `effective_mtu`,
`fixed_mss`, `mss_clamp_enabled`, same validation) and derives its own values; mini-site passes
`mtu_policy = local.mtu_policy` to each of them. Two forms: `site_mtu` alone
(`effective_mtu = site_mtu`, `fixed_mss = site_mtu - 40`), or an explicit `effective_mtu` + `fixed_mss`.

| Hop | What the policy sets |
|---|---|
| wireguard kube pods (edge, hub, hub-ros) | tunnel interface MTU `effective_mtu`; inbound TCP MSS clamp `fixed_mss` (the route-PMTU clamp on the outbound side is always on) |
| RouterOS tunnel `wg-hub-ros` | interface MTU `effective_mtu`; MSS by `clamp-to-pmtu` (`fixed_mss` is not applied) |
| ipt-server, border-router | TCP MSS clamp `fixed_mss` |
| Firezone | MSS clamp `min(fixed_mss, firezone_client_mtu - 40)`; the client's `wg-firezone` MTU is set by Firezone, not by garuda (`firezone_client_mtu`, default 1280) |
| `border` NAD (since #216) | bridge and pod veth MTU `effective_mtu`, through the `garuda_k8s` module's `mtu_policy` |

`mss_clamp_enabled = false` switches the fixed-MSS clamps off (rollback and per-layer details:
[MTU/MSS runbook](../../docs/operations/operator-runbook-mtu-mss-clamping.md)).

`border` must match the tunnels: with the default 1500 bridge an oversized inbound packet is
forwarded into a pod whose tunnel egress is narrower, and the pod's frag-needed reply leaves via the
pod's default route and is dropped by the host as a martian, so UDP PMTUD black-holes; at the tunnel
MTU the host itself answers with frag-needed.

To change it, edit `local.mtu_policy` and apply. The wireguard, border-router and ipt-server pods roll
because their pod templates carry the derived values (env, ConfigMap checksum); a NAD MTU reaches only
new sandboxes, so the `garuda_guest` of every `border`-attached workload also takes `mtu_policy` as a
hash-only input (since #216), which rolls Firezone (its MSS is capped by the client MTU and does not
change). The host's `border` bridge MTU then follows its smallest port by itself; do not set it by hand.

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
