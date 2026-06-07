# Module Execution Model

> **Rewrite note.** This document previously described the removed
> `linux_apply` → Ansible → Docker Compose execution model. That model was
> eliminated in the k3s migration. This page now describes the current
> Terraform → Helm/Kubernetes execution model.

## Chain

```
compute module (yc_compute_host / gcp_compute_host)
  -> outputs connection_data (including instance_token, SSH host)
  -> garuda-tunnel (SSH tunnel + kubeconfig fetch + server: rewrite)
  -> patched kubeconfig at local path
  -> garuda/ providers.tf (helm.<alias> + kubernetes.<alias> providers)
  -> workload module (wireguard/kube, firezone/kube, ipt_server/kube, ...)
  -> helm_release resource -> Helm chart apply -> Kubernetes Deployment/Service/...
  -> FRR sidecar container (same pod network namespace as workload)
```

## Layers

**Compute modules** (`yc_compute_host`, `gcp_compute_host`) provision VMs and
output `connection_data`. They are responsible for:

- Creating the host VM.
- Injecting SSH keys and k3s cloud-init user-data (via `modules/k3s_cloud_init`).
- Populating `connection_data.instance_token` from the cloud instance ID.

**`modules/k3s_cloud_init`** generates the cloud-init user-data fragment that
installs and configures k3s on first boot. It is consumed by compute modules via
their `user_data_parts` input.

**`garuda-tunnel`** (external tool, run before `tofu apply`) opens SSH tunnels to
each k3s node, fetches `/etc/rancher/k3s/k3s.yaml`, rewrites `server:` to the
local forwarded port, and materializes the patched kubeconfig at a local path. It
writes a JSON state file (`OutputSchema`) that the `garuda/` unit reads via
`var.tunnel_path`.

**`garuda/` provider configuration** (`providers.tf`) reads per-node kubeconfig
paths from `local.edges_kubeconfig_path` and `local.hub_kubeconfig_path` (derived
from the tunnel state JSON). Each k3s cluster gets a pair of explicit aliased
`helm` and `kubernetes` providers. When `var.tunnel_path` is empty (unit tests,
`tofu init`), providers fall back to an inert loopback configuration.

**`modules/garuda_k8s`** bootstraps each k3s cluster: creates the `garuda`
namespace, installs Multus and Whereabouts CNI DaemonSets, and creates
`NetworkAttachmentDefinition` resources for the `backbone` and `border` secondary
networks. This is a prerequisite for all workload modules on that cluster.

**Workload modules** (`wireguard/kube`, `firezone/kube`, `ipt_server/kube`,
`border_router`, ...) accept workload-specific configuration and create a
`helm_release` resource. The Helm chart bundles the workload Deployment, Services,
ConfigMaps, and Secrets. If the workload needs OSPF, the chart declares
`frr-sidecar` from `oci://ghcr.io/garuda-tunnel/charts` as a Helm dependency and renders
the FRR sidecar container into the same pod.

## Dependency rule

Workload modules must declare exactly one explicit `depends_on`, and that
dependency must be the **same-cluster `garuda_k8s` module only**:

```hcl
module "wireguard_kube_hub" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//kube?ref=v0.2.0"
  # ... inputs ...
  depends_on = [module.garuda_k8s_hub]
}
```

**Why.** The `garuda_k8s` module installs Multus and creates the NADs that
workload pods require. Without this `depends_on`, Terraform may schedule the
workload `helm_release` before the NADs exist, causing pod scheduling failures.

**Cross-cluster `depends_on` is prohibited.** It forces Terraform to track the
full output graph of the dependency and causes re-apply whenever any output of
that module changes. Use OSPF or application-level retry for cross-cluster
coordination.

**Provider aliases per cluster.** Because Terraform does not support `for_each`
on provider aliases at the module level, each k3s cluster requires explicit
aliased `helm.<slug>` and `kubernetes.<slug>` providers in `providers.tf`, and
explicit module blocks in `main.tf`. Adding a new edge cluster requires: a new
provider alias pair, a new `garuda_k8s` module block, and new workload module
blocks for that cluster.

## Image build and publish pipeline

Workload container images are built and published by their respective component
repositories:

| Component         | Repository                          | Image                                     |
|-------------------|-------------------------------------|-------------------------------------------|
| WireGuard         | `garuda-tunnel/wireguard`          | `ghcr.io/garuda-tunnel/garuda-wireguard`        |
| Firezone          | `garuda-tunnel/firezone`           | `ghcr.io/garuda-tunnel/garuda-firezone`         |
| Router (ipt_server) | `garuda-tunnel/router`           | `ghcr.io/garuda-tunnel/garuda-ipt-server`       |
| Border Router     | `garuda-tunnel/border-router`      | `ghcr.io/garuda-tunnel/garuda-border-router`    |
| conntrack-log     | `garuda-tunnel/audit`              | `ghcr.io/garuda-tunnel/garuda-conntrack-log`    |
| FRR sidecar       | `garuda-tunnel/frr-sidecar`        | `oci://ghcr.io/garuda-tunnel/charts/frr-sidecar` |

The umbrella publishes no workload images. Image references are defaulted in each
component module's `variables.tf`.

## Related

- [connection_data contract](connection-data.md)
- [Architecture — planes and node roles](../concepts/architecture.md)
- [Prerequisites — garuda-tunnel](../getting-started/prerequisites.md#garuda-tunnel-and-kubeconfigs)
