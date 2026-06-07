# How to Add a WireGuard Tunnel

Garuda supports two tunnel types:

1. **k3s-to-k3s** — both endpoints run as `wireguard/kube` deployments on k3s clusters.
2. **k3s-to-RouterOS** — the hub-side endpoint runs as `wireguard/kube`; the RouterOS side
   is configured by `wireguard/routeros`.

> **Historical note.** Prior to the k3s migration, WireGuard was deployed as a Docker container
> on bare Linux hosts via a compose-era module that has since been removed. The current pattern
> is `wireguard/kube` (from `garuda-tunnel/wireguard`) for all Linux-side WireGuard endpoints.

## k3s-to-k3s tunnel (hub ↔ edge)

Four modules work together:

| Module               | Role                                                              |
|----------------------|-------------------------------------------------------------------|
| `wireguard/tunnel`   | Generates keys and exports per-peer config objects               |
| `wireguard/kube`     | Deploys the WireGuard endpoint on the edge k3s cluster           |
| `wireguard/kube`     | (second call) Deploys the hub-side endpoint on the hub k3s cluster |
| `garuda_k8s`         | Must exist for both clusters before wireguard/kube is instantiated |

This is the pattern used in `examples/mini-site/garuda/main.tf` for the
`wireguard_kube_pt` / `wireguard_kube_de` (edge) and `wireguard_kube_hub` (hub) modules.

### Step 1: Define the tunnel (key generation)

```hcl
module "wireguard_tunnel_eur" {
  source   = "git::https://github.com/garuda-tunnel/wireguard.git//tunnel?ref=v0.2.0"
  name     = "eur"
  env_slug = var.env_slug
  subnet   = "192.0.2.16/28"
  peers = {
    core = {
      address       = "192.0.2.17"
      listen_port   = 51820
      endpoint_host = var.cloudflare_hub.record_name
    }
    edge = {
      address       = "192.0.2.18"
      listen_port   = 51820
      endpoint_host = var.cloudflare_edges["eur"].record_name
    }
  }
}
```

`wireguard/tunnel` emits two name fields per peer:

- `tunnel_name = "${env_slug}-eur"` — env-prefixed. Used by `wireguard/routeros`.
- `kernel_ifname = "eur"` — raw (max 15 chars). Used by `wireguard/kube` as the
  Linux kernel interface name inside the pod.

### Step 2: Deploy the edge-side WireGuard pod

```hcl
module "wireguard_kube_eur" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//kube?ref=v0.2.0"

  providers = {
    helm       = helm.eur
    kubernetes = kubernetes.eur
  }

  namespace       = module.garuda_k8s_eur.namespace
  name            = "wg-eur"
  config          = module.wireguard_tunnel_eur.peers["edge"]
  peer            = module.wireguard_tunnel_eur.peers["core"]
  allowed_nets    = ["0.0.0.0/0"]
  nic_attach      = ["backbone", "border"]
  wireguard_image = var.wireguard_image
  frr_image       = var.frr_sidecar_image
  ospf = {
    router_id         = var.edges["eur"].ospf_router_id_peer
    interfaces        = [module.wireguard_tunnel_eur.peers["edge"].kernel_ifname]
    default_originate = true
  }

  depends_on = [module.garuda_k8s_eur]
}
```

The edge side sets `default_originate = true` so it originates the default route
into the OSPF mesh.

### Step 3: Deploy the hub-side WireGuard pod

```hcl
module "wireguard_kube_hub_eur" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//kube?ref=v0.2.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace       = module.garuda_k8s_hub.namespace
  name            = "wg-eur"
  config          = module.wireguard_tunnel_eur.peers["core"]
  peer            = module.wireguard_tunnel_eur.peers["edge"]
  allowed_nets    = [module.wireguard_tunnel_eur.peers["edge"].subnet]
  nic_attach      = ["backbone", "border"]
  wireguard_image = var.wireguard_image
  frr_image       = var.frr_sidecar_image
  ospf = {
    router_id  = var.edges["eur"].ospf_router_id_hub
    interfaces = [module.wireguard_tunnel_eur.peers["core"].kernel_ifname]
  }

  depends_on = [module.garuda_k8s_hub]
}
```

Both sides must reference their own cluster's `garuda_k8s` module via `depends_on`.
Explicit Helm provider aliases (`helm.eur`, `helm.hub`) must be declared in
`providers.tf` before adding a new cluster — see `examples/mini-site/garuda/providers.tf`
for the alias pattern.

## k3s-to-RouterOS tunnel

Three modules work together:

| Module               | Role                                                          |
|----------------------|---------------------------------------------------------------|
| `wireguard/tunnel`   | Generates keys and exports per-peer config objects           |
| `wireguard/kube`     | Deploys the WireGuard endpoint on the hub k3s cluster        |
| `wireguard/routeros` | Configures the WireGuard interface and OSPF on RouterOS      |

The existing hub-to-RouterOS tunnel (`wireguard_tunnel_hub_ros`,
`wireguard_kube_hub_ros`, `wireguard_routeros_hub_ros`) in
`examples/mini-site/garuda/main.tf` is the canonical reference for this pattern.

### Key distinction: tunnel_name vs kernel_ifname

- `wireguard/kube` uses `kernel_ifname` (raw, no env prefix) as the Linux kernel
  interface name inside the pod.
- `wireguard/routeros` uses `tunnel_name` (env-prefixed) for all RouterOS resource
  names to prevent collisions on shared devices.

Both fields come from the same `wireguard/tunnel` output — pass the same `peers[...]`
object to each module.

### Step 1: Define the tunnel

Add `endpoint_host` on both peers so each side can initiate the handshake:

```hcl
module "wireguard_tunnel_ros" {
  source   = "git::https://github.com/garuda-tunnel/wireguard.git//tunnel?ref=v0.2.0"
  name     = "ros"
  env_slug = var.env_slug
  subnet   = "198.51.100.0/28"
  peers = {
    core = {
      address       = "198.51.100.1"
      listen_port   = 51821
      endpoint_host = var.cloudflare_hub.record_name
    }
    edge = {
      address       = "198.51.100.2"
      listen_port   = 51821
      endpoint_host = var.routeros.management_host
    }
  }
}
```

### Step 2: Deploy hub side (k3s)

```hcl
module "wireguard_kube_hub_ros" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//kube?ref=v0.2.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace       = module.garuda_k8s_hub.namespace
  name            = "wg-hub-ros"
  config          = module.wireguard_tunnel_ros.peers["core"]
  peer            = module.wireguard_tunnel_ros.peers["edge"]
  allowed_nets    = ["0.0.0.0/0", "224.0.0.0/4"]
  nic_attach      = ["backbone"]
  wireguard_image = var.wireguard_image
  frr_image       = var.frr_sidecar_image
  ospf = {
    router_id  = var.hub_ros.ospf_router_id_hub
    interfaces = [module.wireguard_tunnel_ros.peers["core"].kernel_ifname]
  }

  depends_on = [module.garuda_k8s_hub]
}
```

### Step 3: Deploy RouterOS side

```hcl
module "wireguard_routeros_ros" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//routeros?ref=v0.2.0"

  hostname     = var.routeros.hostname
  config       = module.wireguard_tunnel_ros.peers["edge"]
  peer         = module.wireguard_tunnel_ros.peers["core"]
  subnet       = module.wireguard_tunnel_ros.subnet
  allowed_nets = ["0.0.0.0/0"]
  interface_list = "LAN"

  router_id = split("/", var.hub_ros.routeros_cidr)[0]
  ospf_area = "0.0.0.0"
}
```

RouterOS resource names are prefixed with `env_slug` (e.g. `prod-ros`).

## Further reading

- [`wireguard/tunnel` README](https://github.com/garuda-tunnel/wireguard/blob/main/tunnel/README.md)
- [`wireguard/kube` README](https://github.com/garuda-tunnel/wireguard/blob/main/kube/README.md)
- [`wireguard/routeros` README](https://github.com/garuda-tunnel/wireguard/blob/main/routeros/README.md)
- [How to add a workload](add-workload.md)
- [Architecture — WireGuard naming split](../concepts/architecture.md#wireguard-tunnel-naming-split)
