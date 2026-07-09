locals {
  mtu_policy = {
    site_mtu = 1330
  }

  # Garuda chart version deployed via module.garuda_k8s_*.
  # Derived from modules/garuda_k8s/charts/garuda/Chart.yaml (single source of truth)
  # so the profile-rev hash always tracks the actually-deployed chart and cannot go stale.
  garuda_chart_version = module.garuda_k8s_hub.chart_version
}

# --- WireGuard tunnel key-pairs (one tunnel object per edge) ---

module "wireguard_tunnel" {
  for_each = var.edges

  source = "git::https://github.com/garuda-tunnel/wireguard.git//tunnel?ref=v1.1.0"

  name     = "wg_${each.key}"
  env_slug = var.env_slug
  subnet   = local.tunnel_facts[each.key].subnet_cidr
  peers = {
    core = {
      address       = each.value.hub_cidr
      listen_port   = each.value.listen_port
      endpoint_host = var.cloudflare_hub.record_name
    }
    edge = {
      address       = each.value.peer_cidr
      listen_port   = each.value.listen_port
      endpoint_host = var.cloudflare_edges[each.key].record_name
    }
  }
}

# --- Kubernetes namespace and CNI bootstrap: edges ---
# One instanced module over var.edges. Each instance receives its own
# helm.edge[<slug>] / kubernetes.edge[<slug>] provider from providers.tf.
# Adding a third edge is now a single var.edges (inputs.tfvars.yaml) entry.

module "garuda_k8s" {
  for_each = var.edges
  source   = "./modules/garuda_k8s"

  providers = {
    helm       = helm.edge[each.key]
    kubernetes = kubernetes.edge[each.key]
  }

  namespace       = "garuda"
  backbone_subnet = var.backbone_subnet
  border_subnet   = var.border_subnet
}

# --- garuda_guest intent for edge WireGuard workloads ---
# Edge wg: ospf-router profile. Edge WireGuard workloads do NOT originate a default
# route — prod ground truth confirms ONLY ipt-server (transit-provider) originates the
# default (docs/artifacts/2026-06-25-vxxlcx-prod-frr-ground-truth.md §2 / Q4). The
# earlier default_originate="true" (disproven spec §14 #7) is removed.

module "garuda_guest_wireguard_kube_edge" {
  for_each = var.edges
  source   = "./modules/garuda_guest"

  profile              = "ospf-router"
  garuda_chart_version = local.garuda_chart_version
  ospf_router_id       = each.value.ospf_router_id_peer
  networks             = ["backbone", "border"]
  interfaces           = module.wireguard_tunnel[each.key].peers["edge"].kernel_ifname
}

# --- WireGuard Kubernetes workloads: edge side (one deployment per edge) ---

module "wireguard_kube_edge" {
  for_each = var.edges
  source   = "git::https://github.com/garuda-tunnel/wireguard-internal.git//kube?ref=v2.0.0"
  # renovate: datasource=docker depName=ghcr.io/garuda-tunnel/charts/wireguard
  chart_version = "2.0.0"

  providers = {
    helm       = helm.edge[each.key]
    kubernetes = kubernetes.edge[each.key]
  }

  namespace       = module.garuda_k8s[each.key].namespace
  name            = "wg-${each.key}"
  self            = module.wireguard_tunnel[each.key].peers["edge"]
  remote          = module.wireguard_tunnel[each.key].peers["core"]
  wireguard_image = var.wireguard_image
  annotations     = module.garuda_guest_wireguard_kube_edge[each.key].annotations
  labels          = module.garuda_guest_wireguard_kube_edge[each.key].labels
  configmaps      = module.garuda_guest_wireguard_kube_edge[each.key].configmaps
  mtu_policy      = local.mtu_policy
  # No depends_on: module.garuda_k8s[each.key].namespace already builds a
  # per-edge dependency. A module-wide depends_on=[module.garuda_k8s] would
  # serialize every edge against every namespace — do NOT add it.
}

# --- WireGuard tunnel key-pair for hub-ros (RouterOS <-> hub) ---

module "wireguard_tunnel_hub_ros" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//tunnel?ref=v1.1.0"

  name     = "wg_hub_ros"
  env_slug = var.env_slug
  subnet   = local.hub_ros_facts.subnet_cidr
  peers = {
    core = {
      address       = var.hub_ros.hub_cidr
      listen_port   = var.hub_ros.listen_port
      endpoint_host = var.cloudflare_hub.record_name
    }
    edge = {
      address       = var.hub_ros.routeros_cidr
      listen_port   = var.hub_ros.listen_port
      endpoint_host = var.routeros.management_host
    }
  }
}

# --- WireGuard RouterOS module: RouterOS side of hub-ros tunnel ---

module "wireguard_routeros_hub_ros" {
  source = "git::https://github.com/garuda-tunnel/wireguard-internal.git//routeros?ref=v2.0.0"

  hostname       = var.routeros.hostname
  self           = module.wireguard_tunnel_hub_ros.peers["edge"]
  remote         = module.wireguard_tunnel_hub_ros.peers["core"]
  subnet         = local.hub_ros_facts.subnet_cidr
  allowed_nets   = ["0.0.0.0/0", "224.0.0.0/4"]
  interface_list = "LAN"
  mtu_policy     = local.mtu_policy

  ospf_router_id = split("/", var.hub_ros.routeros_cidr)[0]
  ospf_area      = "0.0.0.0"
}

# Default route into the hub-ros bypass routing table. Without this route,
# the per-tunnel PBR rule installed by the endpoint sync script has no nexthop
# and the WG handshake packets are dropped.
resource "routeros_ip_route" "hub_ros_bypass_default" {
  dst_address   = "0.0.0.0/0"
  gateway       = var.routeros_lan_gateway
  routing_table = module.wireguard_routeros_hub_ros.bypass_table_name
  comment       = "garuda: WG handshake bypass default for wg_hub_ros"
}

# --- RouterOS masquerade for VPN -> LAN traffic ---

resource "routeros_ip_firewall_nat" "hub_ros_masquerade" {
  chain         = "srcnat"
  action        = "masquerade"
  out_interface = var.routeros.uplink_interface
  comment       = "garuda: masquerade VPN -> LAN"

  depends_on = [module.wireguard_routeros_hub_ros]
}

# --- Hub-side k3s namespace and CNI bootstrap ---

module "garuda_k8s_hub" {
  source = "./modules/garuda_k8s"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace       = "garuda"
  backbone_subnet = var.backbone_subnet
  border_subnet   = var.border_subnet
}

# --- garuda_guest intent for hub-side edge WireGuard workloads (per edge) ---
# Hub-side wg: ospf-router profile; runs OSPF on backbone + per-edge tunnel iface.
# No default_originate (hub does not inject a default route into OSPF).

module "garuda_guest_wireguard_kube_hub" {
  for_each = var.edges
  source   = "./modules/garuda_guest"

  profile              = "ospf-router"
  garuda_chart_version = local.garuda_chart_version
  ospf_router_id       = each.value.ospf_router_id_hub
  networks             = ["backbone", "border"]
  interfaces           = "backbone,${module.wireguard_tunnel[each.key].peers["core"].kernel_ifname}"
}

# --- Hub-side WireGuard kube deployments (one per edge tunnel) ---

module "wireguard_kube_hub" {
  for_each = var.edges
  source   = "git::https://github.com/garuda-tunnel/wireguard-internal.git//kube?ref=v2.0.0"
  # renovate: datasource=docker depName=ghcr.io/garuda-tunnel/charts/wireguard
  chart_version = "2.0.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace       = module.garuda_k8s_hub.namespace
  name            = "wg-${each.key}"
  self            = module.wireguard_tunnel[each.key].peers["core"]
  remote          = module.wireguard_tunnel[each.key].peers["edge"]
  wireguard_image = var.wireguard_image
  annotations     = module.garuda_guest_wireguard_kube_hub[each.key].annotations
  labels          = module.garuda_guest_wireguard_kube_hub[each.key].labels
  configmaps      = module.garuda_guest_wireguard_kube_hub[each.key].configmaps
  mtu_policy      = local.mtu_policy

  depends_on = [module.garuda_k8s_hub]
}

# --- garuda_guest intent for hub-ros WireGuard workload ---
# Hub-ros: ospf-router profile; redistributes kernel routes so RouterOS learns
# backbone subnets via OSPF. Transit consumer (PBR) for RouterOS traffic.

module "garuda_guest_wireguard_kube_hub_ros" {
  source = "./modules/garuda_guest"

  profile              = "ospf-router"
  garuda_chart_version = local.garuda_chart_version
  ospf_router_id       = var.hub_ros.ospf_router_id_hub
  networks             = ["backbone"]
  interfaces           = "backbone,${module.wireguard_tunnel_hub_ros.peers["core"].kernel_ifname}"
  redistribute         = "kernel"
  transit_interfaces   = "wg-hub-ros"
}

# --- Hub-side WireGuard kube deployment for RouterOS tunnel ---

module "wireguard_kube_hub_ros" {
  source = "git::https://github.com/garuda-tunnel/wireguard-internal.git//kube?ref=v2.0.0"
  # renovate: datasource=docker depName=ghcr.io/garuda-tunnel/charts/wireguard
  chart_version = "2.0.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace       = module.garuda_k8s_hub.namespace
  name            = "wg-hub-ros"
  self            = module.wireguard_tunnel_hub_ros.peers["core"]
  remote          = module.wireguard_tunnel_hub_ros.peers["edge"]
  wireguard_image = var.wireguard_image
  annotations     = module.garuda_guest_wireguard_kube_hub_ros.annotations
  labels          = module.garuda_guest_wireguard_kube_hub_ros.labels
  configmaps      = module.garuda_guest_wireguard_kube_hub_ros.configmaps
  mtu_policy      = local.mtu_policy

  depends_on = [module.garuda_k8s_hub]
}

# --- cert-manager (hub) ---

module "cert_manager" {
  source = "./modules/cert_manager"

  providers = {
    helm = helm.hub
  }

  email                         = var.cert_manager_email
  acme_server                   = var.cert_manager_acme_server
  allow_reserved_contact_domain = var.cert_manager_allow_reserved_contact_domain

  depends_on = [module.garuda_k8s_hub]
}

# --- Gateway API platform (hub) ---

module "k8s_gateway_bootstrap" {
  source = "./modules/k8s_gateway_bootstrap"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace           = "gateway-system"
  gateway_class_name  = "traefik"
  cluster_issuer_name = module.cert_manager.cluster_issuer_name
  # cert_secret_name is derived as "<name>-tls" to keep the secret
  # identity in lockstep with the listener identity. The smoke phase
  # uses the same convention to look up the issued cert.
  hostnames = [for entry in [
    { name = "hub", hostname = local.firezone_fqdn },
    { name = "panel", hostname = local.remnawave_panel_fqdn },
    { name = "sub", hostname = local.remnawave_sub_fqdn },
  ] : merge(entry, { cert_secret_name = "${entry.name}-tls" })]

  depends_on = [module.cert_manager]
}

# --- garuda_guest intent for Remnawave node workload ---
# The frr sidecar uses var.ospf_router_ids.remnawave_node as its OSPF router-id.
# The node chart separately owns dummy0=172.30.0.45/32 via node_routing below;
# dummy0 is passive so the /32 is advertised without forming adjacencies.

module "garuda_guest_remnawave_node" {
  source = "./modules/garuda_guest"

  profile              = "ospf-router"
  garuda_chart_version = local.garuda_chart_version
  networks             = ["backbone"]
  ospf_router_id       = var.ospf_router_ids.remnawave_node
  interfaces           = "backbone"
  passive_interfaces   = "dummy0"
  default_originate    = "false"
}

# --- Remnawave panel + node (hub, k8s) ---

module "remnawave_panel" {
  source = "git::https://github.com/garuda-tunnel/remnawave-internal.git//kube?ref=v0.1.0"
  # renovate: datasource=docker depName=ghcr.io/garuda-tunnel/charts/remnawave-panel
  chart_version = "0.1.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace     = module.garuda_k8s_hub.namespace
  name          = "remnawave-panel"
  remnawave_dir = "/opt/garuda/remnawave"
  panel_fqdn    = local.remnawave_panel_fqdn
  sub_fqdn      = local.remnawave_sub_fqdn
  gateway_ref = {
    name      = module.k8s_gateway_bootstrap.gateway_name
    namespace = module.k8s_gateway_bootstrap.gateway_namespace
  }

  node_enabled = true
  node_name    = local.remnawave_node_name
  node_registration = {
    panel_base_url        = "https://remnawave-panel.${module.garuda_k8s_hub.namespace}.svc.cluster.local:3000"
    api_token_secret_name = local.remnawave_node_panel_api_token_secret_name
    api_token_secret_key  = "token"
    config_profile_uuid   = "default-profile-uuid"
    active_inbounds       = ["hysteria-udp-${local.remnawave_node_hysteria_udp_port}"]
  }
  node_routing = {
    ospf_router_id        = "172.30.0.45"
    ipt_server_address    = "172.30.0.32"
    cluster_cidrs         = ["10.42.0.0/16"]
    service_cidrs         = ["10.43.0.0/16"]
    static_default_metric = 200
  }
  node_pod_annotations = module.garuda_guest_remnawave_node.annotations
  node_pod_labels      = module.garuda_guest_remnawave_node.labels

  depends_on = [module.garuda_k8s_hub, module.cert_manager, module.k8s_gateway_bootstrap]
}

# --- garuda_guest intent for Firezone workload ---
# Firezone: ospf-router profile; redistributes connected+kernel routes.
# PBR transit consumer for Firezone client traffic (transit_interfaces=wg-firezone).
# wg-firezone is a kernel WireGuard interface (not a Multus NAD); it is NOT in
# workload_nads. Firezone needs backbone (OSPF mesh) + border (ISP egress).

module "garuda_guest_firezone_kube" {
  source = "./modules/garuda_guest"

  profile              = "ospf-router"
  garuda_chart_version = local.garuda_chart_version
  ospf_router_id       = var.ospf_router_ids.firezone
  networks             = ["backbone", "border"]
  interfaces           = "backbone,wg-firezone"
  passive_interfaces   = "wg-firezone"
  redistribute         = "connected,kernel"
  transit_interfaces   = "wg-firezone"
}

# --- Firezone (hub, k8s) ---

module "firezone_kube" {
  source = "git::https://github.com/garuda-tunnel/firezone-internal.git//kube?ref=v1.2.0"
  # renovate: datasource=docker depName=ghcr.io/garuda-tunnel/charts/firezone
  chart_version = "1.2.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace      = module.garuda_k8s_hub.namespace
  firezone_dir   = local.firezone_facts.directory
  firezone_image = var.fz_firezone_image
  server_fqdn    = local.firezone_fqdn
  admin_email    = local.firezone_facts.admin_email
  admin_password = local.firezone_facts.admin_password
  client_subnet  = local.firezone_facts.client_subnet
  mtu_policy     = local.mtu_policy
  gateway_ref = {
    name      = module.k8s_gateway_bootstrap.gateway_name
    namespace = module.k8s_gateway_bootstrap.gateway_namespace
  }
  annotations = module.garuda_guest_firezone_kube.annotations
  labels      = module.garuda_guest_firezone_kube.labels
  configmaps  = module.garuda_guest_firezone_kube.configmaps
  ospf        = null

  encryption_secrets = var.firezone_encryption_secrets

  oidc_providers = {
    google = {
      client_id     = var.firezone_oidc_google_client_id
      client_secret = var.firezone_oidc_google_client_secret
      label         = "Google"
    }
  }

  depends_on = [module.garuda_k8s_hub, module.cert_manager, module.k8s_gateway_bootstrap]
}

# --- garuda_guest intent for ipt_server workload ---
# ipt_server: transit-provider profile. transit_interfaces MUST be empty (XOR invariant).
# The MAP injects the frr-sidecar with PBR_TRANSIT_TAG=201 at pod admission.

module "garuda_guest_ipt_server_kube" {
  source = "./modules/garuda_guest"

  profile              = "transit-provider"
  garuda_chart_version = local.garuda_chart_version
  ospf_router_id       = var.ospf_router_ids.ipt_server
  networks             = ["backbone"]
  interfaces           = "backbone"
  # transit_interfaces intentionally absent: XOR with profile=transit-provider
}

# --- ipt_server (hub, k8s) ---

module "ipt_server_kube" {
  source = "git::https://github.com/garuda-tunnel/router-internal.git//kube?ref=v1.2.9"
  # renovate: datasource=docker depName=ghcr.io/garuda-tunnel/charts/ipt-server
  chart_version = "1.2.9"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace        = module.garuda_k8s_hub.namespace
  ipt_server_image = var.ipt_server_image
  powerdns_image   = var.ipt_powerdns_image
  routes           = local.ipt_routes
  nic_attach       = ["backbone"]
  pbr_interfaces   = ["backbone"]
  pinning_egress   = local.pinning_egress
  annotations      = module.garuda_guest_ipt_server_kube.annotations
  labels           = module.garuda_guest_ipt_server_kube.labels
  configmaps       = module.garuda_guest_ipt_server_kube.configmaps
  ospf             = null
  mtu_policy       = local.mtu_policy

  depends_on = [module.garuda_k8s_hub]
}

# --- garuda_guest intent for border_router workload ---
# Border: border profile. No interfaces/redistribute; egress-setup init container
# uses ospf.router_id passed directly to the border_router module (Decision #5 exception).

module "garuda_guest_border_router" {
  source = "./modules/garuda_guest"

  profile              = "border"
  garuda_chart_version = local.garuda_chart_version
  networks             = ["backbone", "border"]
  # border runs OSPF on backbone; router-id flows to the net.garuda-tunnel/router-id
  # annotation -> MAP ROUTER_ID env -> frr-sidecar (border profile template ${ROUTER_ID}).
  # Same value also passed to the guest module's ospf{} for the egress-setup initContainer.
  ospf_router_id = var.border_router.router_id
}

# --- Local border egress (hub) ---
# border_router is "a WireGuard pod without the tunnel": it owns the local
# border egress (dummy0 /32 advertised via OSPF, default via the discovered
# border gateway, masquerade) so ipt_server can route RU/local traffic to it via
# gw=<router_id> instead of the broken gateway-less dev=border nexthop.
module "border_router" {
  source = "git::https://github.com/garuda-tunnel/border-router-internal.git?ref=v1.2.0"
  # renovate: datasource=docker depName=ghcr.io/garuda-tunnel/charts/border-router
  chart_version = "1.2.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace   = module.garuda_k8s_hub.namespace
  name        = "border-router"
  image       = var.border_router_image
  annotations = module.garuda_guest_border_router.annotations
  labels      = module.garuda_guest_border_router.labels
  configmaps  = module.garuda_guest_border_router.configmaps
  # border_router keeps ospf.router_id for the workload-native egress-setup
  # init container (BR_ADDRESS derivation). Decision #5 exception.
  ospf       = { router_id = var.border_router.router_id }
  mtu_policy = local.mtu_policy

  depends_on = [module.garuda_k8s_hub]
}
