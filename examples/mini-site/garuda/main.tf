# --- WireGuard tunnel key-pairs (one tunnel object per edge) ---

module "wireguard_tunnel" {
  for_each = var.edges

  source = "git::https://github.com/garuda-tunnel/wireguard.git//tunnel?ref=v0.5.0"

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
# One explicit module per edge. Each module receives its own
# helm.<slug> / kubernetes.<slug> aliased providers from providers.tf.
# Adding a third edge requires three changes: a new var.edges entry,
# a new alias pair in providers.tf, and a new module block here.

module "garuda_k8s_pt" {
  source = "./modules/garuda_k8s"

  providers = {
    helm       = helm.pt
    kubernetes = kubernetes.pt
  }

  namespace       = "garuda"
  backbone_subnet = var.backbone_subnet
  border_subnet   = var.border_subnet
  kubeconfig_path = local.edges_kubeconfig_path["pt"]
}

module "garuda_k8s_de" {
  source = "./modules/garuda_k8s"

  providers = {
    helm       = helm.de
    kubernetes = kubernetes.de
  }

  namespace       = "garuda"
  backbone_subnet = var.backbone_subnet
  border_subnet   = var.border_subnet
  kubeconfig_path = local.edges_kubeconfig_path["de"]
}

# --- WireGuard Kubernetes workloads: edge side (one deployment per edge) ---

module "wireguard_kube_pt" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//kube?ref=v0.5.0"

  providers = {
    helm       = helm.pt
    kubernetes = kubernetes.pt
  }

  namespace       = module.garuda_k8s_pt.namespace
  name            = "wg-pt"
  config          = local.wireguard_kube_inputs["pt"].config
  peer            = local.wireguard_kube_inputs["pt"].peer
  allowed_nets    = local.wireguard_kube_inputs["pt"].allowed_nets
  nic_attach      = ["backbone", "border"]
  wireguard_image = var.wireguard_image
  frr_image       = var.frr_sidecar_image
  ospf            = local.wireguard_kube_inputs["pt"].ospf

  depends_on = [module.garuda_k8s_pt]
}

module "wireguard_kube_de" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//kube?ref=v0.5.0"

  providers = {
    helm       = helm.de
    kubernetes = kubernetes.de
  }

  namespace       = module.garuda_k8s_de.namespace
  name            = "wg-de"
  config          = local.wireguard_kube_inputs["de"].config
  peer            = local.wireguard_kube_inputs["de"].peer
  allowed_nets    = local.wireguard_kube_inputs["de"].allowed_nets
  nic_attach      = ["backbone", "border"]
  wireguard_image = var.wireguard_image
  frr_image       = var.frr_sidecar_image
  ospf            = local.wireguard_kube_inputs["de"].ospf

  depends_on = [module.garuda_k8s_de]
}

# --- WireGuard tunnel key-pair for hub-ros (RouterOS <-> hub) ---

module "wireguard_tunnel_hub_ros" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//tunnel?ref=v0.5.0"

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
  source = "git::https://github.com/garuda-tunnel/wireguard.git//routeros?ref=v0.5.0"

  hostname       = var.routeros.hostname
  config         = module.wireguard_tunnel_hub_ros.peers["edge"]
  peer           = module.wireguard_tunnel_hub_ros.peers["core"]
  subnet         = local.hub_ros_facts.subnet_cidr
  allowed_nets   = ["0.0.0.0/0", "224.0.0.0/4"]
  interface_list = "LAN"

  router_id = split("/", var.hub_ros.routeros_cidr)[0]
  ospf_area = "0.0.0.0"
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
  kubeconfig_path = local.hub_kubeconfig_path
}

# --- Hub-side WireGuard kube deployments (one per edge tunnel) ---

module "wireguard_kube_hub" {
  for_each = var.edges
  source   = "git::https://github.com/garuda-tunnel/wireguard.git//kube?ref=v0.5.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace       = module.garuda_k8s_hub.namespace
  name            = "wg-${each.key}"
  config          = local.wireguard_kube_hub_inputs[each.key].config
  peer            = local.wireguard_kube_hub_inputs[each.key].peer
  allowed_nets    = local.wireguard_kube_hub_inputs[each.key].allowed_nets
  nic_attach      = ["backbone", "border"]
  wireguard_image = var.wireguard_image
  frr_image       = var.frr_sidecar_image
  ospf            = local.wireguard_kube_hub_inputs[each.key].ospf

  depends_on = [module.garuda_k8s_hub]
}

# --- Hub-side WireGuard kube deployment for RouterOS tunnel ---

module "wireguard_kube_hub_ros" {
  source = "git::https://github.com/garuda-tunnel/wireguard.git//kube?ref=v0.5.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace       = module.garuda_k8s_hub.namespace
  name            = "wg-hub-ros"
  config          = local.wireguard_kube_hub_ros_inputs.config
  peer            = local.wireguard_kube_hub_ros_inputs.peer
  allowed_nets    = local.wireguard_kube_hub_ros_inputs.allowed_nets
  nic_attach      = ["backbone"]
  wireguard_image = var.wireguard_image
  frr_image       = var.frr_sidecar_image
  ospf            = local.wireguard_kube_hub_ros_inputs.ospf
  # Mirrors locals.tf:85 transit.interfaces wiring.
  # The FRR sidecar exports PBR_TRANSIT_INTERFACES=wg-hub-ros so
  # transit_watcher adds `ip rule iif wg-hub-ros lookup 201` and resolves
  # the OSPF-advertised default route into kernel table 201.
  transit = {
    interfaces = ["wg-hub-ros"]
  }

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
    { name = "hub", hostname = local.firezone_fqdn }
  ] : merge(entry, { cert_secret_name = "${entry.name}-tls" })]

  depends_on = [module.cert_manager]
}

# --- Firezone (hub, k8s) ---

module "firezone_kube" {
  source = "git::https://github.com/garuda-tunnel/firezone.git//kube?ref=v0.5.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace      = module.garuda_k8s_hub.namespace
  firezone_dir   = local.firezone_facts.directory
  firezone_image = var.fz_firezone_image
  frr_image      = var.frr_sidecar_image
  server_fqdn    = local.firezone_fqdn
  admin_email    = local.firezone_facts.admin_email
  admin_password = local.firezone_facts.admin_password
  client_subnet  = local.firezone_facts.client_subnet
  gateway_ref = {
    name      = module.k8s_gateway_bootstrap.gateway_name
    namespace = module.k8s_gateway_bootstrap.gateway_namespace
  }
  ospf = local.firezone_kube_ospf
  # Mirrors locals.tf:103 transit.interfaces wiring.
  # The FRR sidecar exports PBR_TRANSIT_INTERFACES=wg-firezone so
  # transit_watcher routes Firezone client traffic via OSPF-discovered
  # transit nexthops in kernel table 201.
  transit = {
    interfaces = ["wg-firezone"]
  }

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

# --- ipt_server (hub, k8s) ---

module "ipt_server_kube" {
  source = "git::https://github.com/garuda-tunnel/router.git//kube?ref=v0.4.2"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace        = module.garuda_k8s_hub.namespace
  ipt_server_image = var.ipt_server_image
  powerdns_image   = var.ipt_powerdns_image
  frr_image        = var.frr_sidecar_image
  routes           = local.ipt_routes
  nic_attach       = ["backbone"]
  pbr_interfaces   = ["backbone"]
  pinning_egress   = local.pinning_egress
  ospf             = local.ipt_server_kube_ospf

  depends_on = [module.garuda_k8s_hub]
}

# --- Local border egress (hub) ---
# border_router is "a WireGuard pod without the tunnel": it owns the local
# border egress (dummy0 /32 advertised via OSPF, default via the discovered
# border gateway, masquerade) so ipt_server can route RU/local traffic to it via
# gw=<router_id> instead of the broken gateway-less dev=border nexthop.
module "border_router" {
  source = "git::https://github.com/garuda-tunnel/border-router.git?ref=v0.4.0"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace = module.garuda_k8s_hub.namespace
  name      = "border-router"
  image     = var.border_router_image
  frr_image = var.frr_sidecar_image
  ospf      = { router_id = var.border_router.router_id }

  depends_on = [module.garuda_k8s_hub]
}
