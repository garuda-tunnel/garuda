# Module Index

This page lists Garuda's Terraform/OpenTofu modules and links to their component
READMEs. Full variable tables live in the module source or its README.

## Compute modules

These modules provision cloud VMs and output `connection_data`. They require
`env_slug` because they create resources in shared cloud namespaces. k3s is
bootstrapped via `modules/k3s_cloud_init` cloud-init user-data.

| Module               | Cloud           | `env_slug`   | README                                               |
|----------------------|-----------------|-------------|------------------------------------------------------|
| `yc_compute_host`    | Yandex Cloud    | **required** | [README](../../modules/yc_compute_host/README.md)   |
| `gcp_compute_host`   | GCP             | **required** | [README](../../modules/gcp_compute_host/README.md)  |

## Infrastructure modules

| Module                    | Purpose                                                  | README                                                     |
|---------------------------|----------------------------------------------------------|------------------------------------------------------------|
| `k3s_cloud_init`          | k3s cloud-init user-data fragment for compute provisioning | [README](../../modules/k3s_cloud_init/README.md)         |
| `garuda_k8s`              | Namespace bootstrap: Multus, Whereabouts, backbone/border NADs | [README](../../modules/garuda_k8s/README.md)         |
| `cert_manager`            | cert-manager with Let's Encrypt ClusterIssuer on hub     | [README](../../modules/cert_manager/README.md)             |
| `k8s_gateway_bootstrap`   | Gateway API (Traefik IngressRoute, TLS) on hub           | [README](../../modules/k8s_gateway_bootstrap/README.md)    |

## WireGuard modules

`wireguard/tunnel` requires `env_slug` because it produces `tunnel_name` consumed
by RouterOS (shared namespace). `wireguard/kube` and `wireguard/routeros` do not
declare `env_slug`; they receive the scoped names from `wireguard/tunnel` outputs.

Source: `garuda-tunnel/garuda-wireguard` (`git::https://github.com/garuda-tunnel/garuda-wireguard.git`)

| Module                  | Purpose                                                    | `env_slug`   | README                                                                                         |
|-------------------------|------------------------------------------------------------|-------------|------------------------------------------------------------------------------------------------|
| `wireguard/tunnel`      | Key generation and per-peer config for a tunnel pair       | **required** | [README](https://github.com/garuda-tunnel/garuda-wireguard/blob/main/tunnel/README.md)              |
| `wireguard/kube`        | Deploy a WireGuard peer on k3s (Kubernetes)                | not used     | [README](https://github.com/garuda-tunnel/garuda-wireguard/blob/main/kube/README.md)                |
| `wireguard/routeros`    | RouterOS WireGuard tunnel, endpoint bypass, OSPF           | not used     | [README](https://github.com/garuda-tunnel/garuda-wireguard/blob/main/routeros/README.md)            |

### WireGuard naming split

`wireguard/tunnel` emits two name fields per peer:

| Output field      | Value                                      | Consumer                   |
|-------------------|--------------------------------------------|----------------------------|
| `tunnel_name`     | `"${env_slug}-${name-hyphenated}"`         | `wireguard/routeros`       |
| `kernel_ifname`   | `"${name-hyphenated}"` (max 15 chars)      | `wireguard/kube`           |

## Workload modules

These modules live in external component repositories and are consumed via git refs.

| Module             | Source                                                                        | Purpose                                                    | README                                                                                       |
|--------------------|-------------------------------------------------------------------------------|------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `firezone/kube`    | `git::https://github.com/garuda-tunnel/garuda-firezone.git//kube?ref=v0.2.0`       | Firezone deployment on the hub k3s                         | [README](https://github.com/garuda-tunnel/garuda-firezone/blob/main/kube/README.md)               |
| `ipt_server/kube`  | `git::https://github.com/garuda-tunnel/garuda-router.git//kube?ref=v0.1.0`         | ipt_server + PowerDNS deployment on the hub k3s            | [README](https://github.com/garuda-tunnel/garuda-router/blob/main/kube/README.md)                 |
| `border_router`    | `git::https://github.com/garuda-tunnel/garuda-border-router.git?ref=v0.1.0`        | Border egress pod — dummy0 /32 advertised via OSPF         | [README](https://github.com/garuda-tunnel/garuda-border-router/blob/main/README.md)               |

## Library modules

| Module              | Source                                    | Purpose                                                    | README                                                                                       |
|---------------------|-------------------------------------------|------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `frr-sidecar`       | `oci://ghcr.io/garuda-tunnel/charts/frr-sidecar` | Library Helm chart — FRR sidecar for OSPF-bearing pods   | [README](https://github.com/garuda-tunnel/garuda-frr-sidecar/blob/main/README.md)                 |

## Required `env_slug` summary

| Module               | `env_slug` required | What it scopes                                                |
|----------------------|---------------------|---------------------------------------------------------------|
| `yc_compute_host`    | yes                 | Instance name, hostname (per-VPC FQDN), security group, disks |
| `gcp_compute_host`   | yes                 | Instance name, hostname (per-project FQDN), firewall, disks   |
| `wireguard/tunnel`   | yes                 | `tunnel_name` output (RouterOS resource naming)               |
| `wireguard/routeros` | no                  | Receives scoped `tunnel_name` from `wireguard/tunnel`         |
| all workload modules | no                  | Cluster-local namespace, scoped by cluster identity           |

## Related

- [connection_data contract](connection-data.md)
- [Module execution model](module-execution-model.md)
- [Architecture — env_slug mental model](../concepts/architecture.md#multi-stack-isolation-and-envslug)
