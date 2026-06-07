# Reference Topology Walkthrough

The `examples/mini-site/` directory inside this repository is the canonical
sanitized reference topology. It demonstrates a three-node Garuda deployment:

| Node       | Role          | Responsibilities                                             |
|------------|---------------|--------------------------------------------------------------|
| hub        | hub           | Firezone, `ipt_server`, WireGuard hub peers, border router   |
| pt, de     | egress edges  | foreign-geography uplinks, each runs a WireGuard k3s workload|
| routeros   | server-client | RouterOS branch device behind a WireGuard tunnel             |

This is a template for operators to adapt — not production credentials or real
cloud IDs. See `examples/mini-site/inputs.tfvars.yaml.example` for the variable
shape.

## Unit structure

```
examples/mini-site/
  infra/           # Provisions compute, DNS, and k3s cloud-init
  garuda/          # Deploys workloads (consumes infra outputs)
  smoke/           # End-to-end verification
  inputs.tfvars.yaml.example
```

## infra/ unit

The `infra/` unit provisions cloud compute, DNS records, and k3s cloud-init
user-data. It exports facts that `garuda/` consumes:

| Output                  | Type                     | Consumer                                       |
|-------------------------|--------------------------|------------------------------------------------|
| `connection_data_hub`   | `connection_data` object | SSH identity for garuda-tunnel (hub)           |
| `connection_data_edges` | map of `connection_data` | SSH identities for garuda-tunnel (edges)       |
| `cloudflare_hub`        | DNS record object        | Hub FQDN used as WireGuard endpoint host       |
| `cloudflare_edges`      | map of DNS records       | Edge FQDNs used as WireGuard endpoint hosts    |
| `routeros`              | RouterOS bootstrap object| `wireguard/routeros` module                    |

k3s is bootstrapped on each VM via `modules/k3s_cloud_init` cloud-init user-data
parts, which are injected into the compute module's `user_data_parts` input.

## garuda/ unit

The `garuda/` unit deploys all workloads in dependency order using the Helm and
Kubernetes Terraform providers:

1. `garuda_k8s` on hub and each edge — namespace bootstrap (Multus, Whereabouts,
   backbone/border NADs).
2. WireGuard deployments:
   - `wireguard/tunnel` (key generation, per-peer config) — one per edge + one for
     the RouterOS tunnel.
   - `wireguard/kube` on each edge (edge side of each tunnel).
   - `wireguard/kube` on hub (hub side of each edge tunnel + hub-RouterOS tunnel).
   - `wireguard/routeros` for the RouterOS device.
3. Hub-only workloads: `cert_manager`, `k8s_gateway_bootstrap`, `firezone/kube`,
   `ipt_server/kube`, `border_router`.

Edge workload modules are created with explicit module blocks per slug (one per
provider alias). Each iteration deploys one WireGuard k3s deployment. The
hub-to-RouterOS path is a single explicit module block, not an iteration.

Kubernetes workload modules depend only on the same-cluster `garuda_k8s` module:

```hcl
module "wireguard_kube_hub" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//kube?ref=v0.2.0"
  # inputs ...
  depends_on = [module.garuda_k8s_hub]
}
```

This is the required pattern — cross-cluster `depends_on` must not be used.

## Provider aliases and kubeconfigs

Each k3s cluster (hub, pt, de) needs its own `helm` and `kubernetes` provider
alias in `providers.tf`. Providers are configured from kubeconfig paths
materialized by `garuda-tunnel` into `local.hub_kubeconfig_path` and
`local.edges_kubeconfig_path[<slug>]`. When `var.tunnel_path` is empty (unit
tests, `tofu init`), providers fall back to an inert loopback branch.

## Key variable concepts

**`edges` map.** Each key corresponds to one egress edge. The `garuda/` unit
uses explicit module blocks per edge slug rather than `for_each` on providers
(Terraform does not support provider `for_each` at the module level). Adding a
third edge requires a new `var.edges` entry, a new alias pair in `providers.tf`,
and new explicit module blocks.

**`env_slug`.** Mandatory for `yc_compute_host`, `gcp_compute_host`,
`wireguard/tunnel`. Scopes all cloud and RouterOS resource names so multiple
stacks can share the same substrate. Two stacks must use different slugs.

**`tunnel_path`.** Absolute path to the JSON file written by `garuda-tunnel`.
The `garuda/` unit reads per-node kubeconfig paths from this file via
`local.edges_kubeconfig_path` and `local.hub_kubeconfig_path`.

## Routing policy

The hub's `ipt_server` module accepts an `ipt_routes_germany_nets` list (and
derives `local.ipt_routes`) that defines geo/domain/CIDR policy. The example in
`inputs.tfvars.yaml.example` starts with an empty list. Populate it with rules to
route specific traffic through the DE or PT edge, or keep it local via the border
router.

Full schema: [routing policy reference](../reference/routing-policy.md).

## Further reading

- [First deploy](first-deploy.md) — step-by-step commands.
- [Architecture](../concepts/architecture.md) — planes and node roles.
- [Module execution model](../reference/module-execution-model.md)
