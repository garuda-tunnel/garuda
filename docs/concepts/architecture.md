# Architecture

## Planes

```
+-----------------------------------------------------------+
|  Control plane (declarative)                              |
|    OpenTofu modules -> Helm releases + Kubernetes objects |
+-----------------------------------------------------------+
|  Data plane (workloads)                                   |
|    VPN tunnels * Access portals * ipt_server *            |
|    FRR sidecars * RouterOS                                |
+-----------------------------------------------------------+
```

The **control plane** decides what should exist: OpenTofu applies Helm releases
and Kubernetes resources via the Helm and Kubernetes Terraform providers.
The **data plane** carries traffic: WireGuard tunnels, Firezone, ipt_server, FRR
sidecars, and RouterOS.

> **Historical note.** Garuda previously used an Ansible role layer plus a
> `linux_apply` Terraform bridge that ran Ansible via `local-exec`, and a Docker
> Compose stack on each host. That execution model was removed in the k3s migration;
> no Ansible roles, no `docker-compose`, no `ospf_injector` runtime operator.

## Node roles

**Hub.** A Linux host running k3s. Workloads on the hub include Firezone (user
access portal), `ipt_server` (policy routing and DNS intercept), WireGuard tunnel
endpoints (one per egress edge and one for the RouterOS device), cert-manager,
and the border router.

**Egress edge.** A Linux host with a public IP in a target geography running
k3s. It accepts a WireGuard tunnel from the hub and lets the mesh exit through
its uplink. Each edge runs a `garuda_k8s` namespace bootstrap and a
`wireguard/kube` deployment.

**RouterOS device.** A MikroTik router that joins the mesh as a client: it
terminates a WireGuard tunnel managed by `wireguard/routeros` and speaks OSPF via
a built-in FRR peer.

## Shared transport networks

Every Garuda k3s node uses two Multus secondary networks created and owned by
the `garuda_k8s` namespace bootstrap module:

- **`backbone`** — control-plane mesh. OSPF adjacencies and inter-pod control
  traffic ride here. Source IPs are preserved (no SNAT).
- **`border`** — egress underlay with masquerade to the host uplink.
  Border is the only place SNAT happens. WireGuard egress pods attached to
  `border` install a masquerade rule; nothing else masquerades.

Whereabouts IPAM assigns addresses from the `backbone_subnet` and `border_subnet`
CIDRs configured in `modules/garuda_k8s`.

## Terraform modules

### Umbrella modules (in this repository)

| Module                        | Role                                                         |
|-------------------------------|--------------------------------------------------------------|
| `modules/garuda_k8s`          | Namespace bootstrap: Multus, Whereabouts, backbone/border NADs |
| `modules/cert_manager`        | cert-manager (Let's Encrypt) on the hub k3s                  |
| `modules/k8s_gateway_bootstrap` | Gateway API (Traefik IngressRoute, TLS) on the hub k3s     |
| `modules/k3s_cloud_init`      | k3s cloud-init user-data fragment for compute provisioning   |
| `modules/yc_compute_host`     | Provision a VM in Yandex Cloud (hub)                         |
| `modules/gcp_compute_host`    | Provision a VM in Google Cloud (edges)                       |

### Component modules (external repos, consumed via git refs)

| Module                  | Source                                                                   | Role                                                    |
|-------------------------|--------------------------------------------------------------------------|---------------------------------------------------------|
| `wireguard/tunnel`      | `git::https://github.com/garuda-tunnel/garuda-wireguard.git//tunnel?ref=v0.2.0` | WireGuard key generation and per-peer config            |
| `wireguard/kube`        | `git::https://github.com/garuda-tunnel/garuda-wireguard.git//kube?ref=v0.2.0`   | WireGuard deployment on k3s (Kubernetes)                |
| `wireguard/routeros`    | `git::https://github.com/garuda-tunnel/garuda-wireguard.git//routeros?ref=v0.2.0` | RouterOS WireGuard tunnel, endpoint bypass, and OSPF |
| `firezone/kube`         | `git::https://github.com/garuda-tunnel/garuda-firezone.git//kube?ref=v0.2.0`   | Firezone deployment on the hub k3s                      |
| `ipt_server/kube`       | `git::https://github.com/garuda-tunnel/garuda-router.git//kube?ref=v0.1.0`     | ipt_server + PowerDNS deployment on the hub k3s         |
| `border_router`         | `git::https://github.com/garuda-tunnel/garuda-border-router.git?ref=v0.1.0`    | Border egress pod — dummy0 /32 advertised via OSPF      |

Full variable contracts: [`docs/reference/modules.md`](../reference/modules.md).

## FRR sidecars

An FRR speaker runs as a sidecar container in the same Kubernetes pod as its
target workload, sharing the pod's network namespace. OSPF and the transit
watcher run in the same netns as the workload without modifying the workload
image.

All OSPF-bearing modules consume the `frr-sidecar` Helm chart from
`oci://ghcr.io/garuda-tunnel/charts` via a `dependencies:` entry in their own
`Chart.yaml`. The library chart lives in the external `garuda-tunnel/garuda-frr-sidecar`
repo and is published as an OCI package to the public ghcr registry.
No sidecar container spec is inlined; no copy of the library chart is vendored.

## Multi-stack isolation and `env_slug`

Garuda allows several stacks (separate environments, tenants, dev/prod) to share
underlying substrate — a single cloud VPC or a single physical RouterOS device.
Modules whose resources live in shared namespaces require a mandatory `env_slug`
to prevent hostname, FQDN, and RouterOS resource collisions.

| Module               | What `env_slug` scopes                                             |
|----------------------|--------------------------------------------------------------------|
| `yc_compute_host`    | Instance name, VM hostname (per-VPC FQDN), security group, disks  |
| `gcp_compute_host`   | Instance name, VM hostname (per-project FQDN), firewall, disks    |
| `wireguard/tunnel`   | `tunnel_name` output (consumed by RouterOS naming)                |

`wireguard/routeros` does not declare `env_slug` directly. It receives the
env-prefixed `tunnel_name` from `wireguard/tunnel` and uses that value for all
RouterOS resource names.

Modules creating only cluster-local resources do not declare `env_slug` — their
namespace is already scoped by the k3s cluster identity. This includes
`wireguard/kube`, `ipt_server/kube`, `firezone/kube`, `border_router`,
`garuda_k8s`, `cert_manager`, and `k8s_gateway_bootstrap`.

`env_slug` is mandatory: 2–24 chars, lowercase alphanumerics and hyphens. Two
stacks must pick different slugs to coexist on shared substrate.

### WireGuard tunnel naming split

`wireguard/tunnel` emits two name fields per peer:

- `tunnel_name = "${env_slug}-${name-hyphenated}"` — env-prefixed, used by
  `wireguard/routeros` for all RouterOS resource names.
- `kernel_ifname = ${name-hyphenated}` — raw (no env prefix), used by
  `wireguard/kube` as the literal Linux kernel interface name. Bounded by
  `IFNAMSIZ=15`. Not env-scoped because Linux interface namespaces are per-pod.

## Further reading

- [Routing model](routing-model.md) — OSPF, transit PBR, and egress pinning concepts.
- [Module execution model](../reference/module-execution-model.md) — how Terraform
  drives Helm releases and Kubernetes resources.
- [Module index](../reference/modules.md) — exact variable contracts.
