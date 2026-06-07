# Prerequisites

## Required CLI tools

| Tool                            | Purpose                                                           |
|---------------------------------|-------------------------------------------------------------------|
| OpenTofu (>= 1.6)               | Provision infrastructure and drive Helm/Kubernetes modules        |
| Terragrunt                      | Orchestrate multi-unit OpenTofu stacks                            |
| Helm                            | Used internally by OpenTofu's Helm provider; `helm` CLI optional  |
| SOPS + age                      | Decrypt secrets in SOPS-encrypted `inputs.tfvars.yaml`            |
| `garuda-tunnel` (via `uvx`)     | Materialize per-node kubeconfigs over SSH tunnels                 |

`kubectl` is useful for ad-hoc cluster inspection but is not required by the
Terraform workflow.

## Cloud credentials

You need credentials for the cloud providers that host your compute. The
`yc_compute_host` module provisions the hub in Yandex Cloud; `gcp_compute_host`
provisions edge nodes in Google Cloud. Credentials are consumed by the respective
Terraform providers.

## SSH key delivery

SSH keys are declared in `operator_ssh_keys` in the `infra/` unit and injected by
compute modules as part of cloud-init. The key is used by `garuda-tunnel` to open
SSH tunnels and fetch kubeconfigs.

## garuda-tunnel and kubeconfigs

Each k3s node generates `/etc/rancher/k3s/k3s.yaml` at first boot. Before applying
the `garuda/` unit you must run `garuda-tunnel` to:

1. Open SSH port-forward tunnels to each node's k3s API server.
2. Fetch and patch the kubeconfig (rewriting `server:` to the local forwarded port).
3. Write the patched kubeconfig to a local path.

The `garuda/` unit reads the path from a tunnel state JSON file via
`var.tunnel_path` and configures the `helm` and `kubernetes` Terraform providers
accordingly.

```bash
# Start garuda-tunnel (example; adjust to your stand's Terragrunt configuration)
uvx garuda-tunnel start --config <stand-tunnel-config>
```

Leave `var.tunnel_path` empty during `tofu init` and `tofu test` runs that do not
require a live cluster; the provider blocks evaluate inertly in that mode.

## Container images

Garuda workload images are pre-built and published to `ghcr.io/garuda-tunnel/garuda-*`
by the `.publish/public-workflows/publish-images.yml` GitHub Actions workflow on
every push to the default branch. Image references are defaulted in each module's
`variables.tf` and can be overridden at the call site.

Published images:

| Image                          | Published as                          |
|--------------------------------|---------------------------------------|
| `garuda-wireguard`             | `ghcr.io/garuda-tunnel/garuda-wireguard`    |
| `garuda-ipt-server`            | `ghcr.io/garuda-tunnel/garuda-ipt-server`   |
| `garuda-powerdns`              | `ghcr.io/garuda-tunnel/garuda-powerdns`     |
| `garuda-frr-sidecar`           | `ghcr.io/garuda-tunnel/garuda-frr-sidecar`  |
| `garuda-firezone`              | `ghcr.io/garuda-tunnel/garuda-firezone`     |
| `garuda-conntrack-log`         | `ghcr.io/garuda-tunnel/garuda-conntrack-log`|
| `garuda-border-router`         | `ghcr.io/garuda-tunnel/garuda-border-router`|

## Further reading

- [Reference topology](reference-topology.md) — in-repo mini-site walkthrough.
- [connection_data contract](../reference/connection-data.md)
