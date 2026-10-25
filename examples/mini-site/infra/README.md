# mini-site / infra

This Terragrunt unit provisions infrastructure and exports the connection facts
that the `garuda/` unit consumes: a hub and an idle test-client VM on Proxmox VE,
two GCP edge VMs, k3s via [k3s-bootstrap](https://github.com/garuda-tunnel/k3s-bootstrap-internal)
on the hub and edges, and the stand's Cloudflare DNS records.

## Responsibilities

- Provision the hub and client VMs on Proxmox (`bpg/proxmox`, native
  cloud-init `initialization` only — no snippets, no custom user-data; there
  is no SSH to the node). The Ubuntu cloud image is a one-time stand
  preparation outside Terraform; pass its volid as `proxmox.image_file_id`.
- Provision the edge VMs on GCP (`modules/gcp_compute_host`).
- Install k3s per node with k3s-bootstrap (`?ref=v0.2.0`): each node is a
  single-member cluster; the Proxmox hub additionally installs
  `qemu-guest-agent` (the cloud image ships none). Host keys are
  trust-on-first-use: a `terraform_data` per node runs `ssh-keyscan` into
  `var.known_hosts_file` (bounded retry, then a clear failure).
- Register DNS records for hub, edges and the panel endpoints via the
  `cloudflare_*` outputs — every record name lives under `var.base_domain`.
- Bootstrap RouterOS tunnel parameters (gated by `routeros_enabled`).

## Outputs consumed by garuda/

| Output                  | Type                    | Used by                                       |
|-------------------------|-------------------------|-----------------------------------------------|
| `connection_data_hub`   | `connection_data` object | consumed by garuda-tunnel + the k3s hub workload modules    |
| `connection_data_edges` | map of `connection_data` | consumed by garuda-tunnel + the k3s edge workload modules   |
| `connection_data_client`| `connection_data` object | test client (`user = "ubuntu"`; the client is not bootstrapped) |
| `cloudflare_hub`        | DNS record object       | hub DNS facts                                 |
| `cloudflare_edges`      | map of DNS record objects | edge DNS facts                              |
| `routeros`              | RouterOS bootstrap object (null when `routeros_enabled = false`) | `wireguard/routeros` module |

All `connection_data_*` bundles carry the stand private key **by path**
(`ssh_private_key_file`); `ssh_private_key` is always null — no key content
crosses the unit boundary (C7).

## Controller prerequisites

- OpenTofu (or Terragrunt around it)
- `uv` (k3s-bootstrap runs its Ansible playbooks controller-side via
  `uv run`)
- `ssh-keyscan` (openssh-client) and `flock` (util-linux) for the
  known_hosts step

**Required operator setting:** k3s-bootstrap verifies host keys with
`StrictHostKeyChecking=yes` but has no known_hosts input of its own — the
scanned file takes effect through the controller environment:

```bash
export ANSIBLE_SSH_ARGS="-o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o UserKnownHostsFile=/absolute/path/to/known_hosts"
```

Use the absolute `known_hosts_file` value (the terragrunt wrapper exports
this). Without it SSH falls back to `~/.ssh/known_hosts`
and every bootstrap host is unknown, so the apply fails.

## Commands

```bash
# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy (run garuda/ destroy first)
terragrunt destroy
```

## Notes

- The Proxmox API token is never a Terraform variable: export
  `PROXMOX_VE_API_TOKEN` before running.
- Keep `known_hosts_file` at a stable path: the keyscan is triggered by host /
  host_generation changes only, so moving the file does not rescan. If you move
  it, replace the scan resources explicitly —
  `terragrunt apply -replace='terraform_data.known_hosts["hub"]'`, and the same
  for `client` and each edge slug — to populate the new file.
- `ssh_public_key_file` must exist at plan time (it is read to seed the VMs);
  keep the matching private key under umask 077 outside VCS.
- `env_slug` is a mandatory input for compute modules in shared-namespace
  deployments. See [modules reference](../../../docs/reference/modules.md).
