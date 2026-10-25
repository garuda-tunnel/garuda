locals {
  # --- Hub FQDN derived from hub_fqdn_prefix + base_domain. ---
  # Shared by Firezone (server_url) and Remnawave subscription Hosts
  # (public address clients dial for the VPN inbounds).
  hub_fqdn             = "${var.hub_fqdn_prefix}.${var.base_domain}"
  firezone_fqdn        = local.hub_fqdn
  remnawave_panel_fqdn = "panel.${var.base_domain}"
  remnawave_sub_fqdn   = "sub.${var.base_domain}"

  # --- Tunnel facts: one subnet_cidr per edge (fed to wireguard_tunnel.subnet). ---
  tunnel_facts = {
    for k, e in var.edges : k => {
      subnet_cidr = "${cidrhost(e.hub_cidr, 0)}/${split("/", e.hub_cidr)[1]}"
    }
  }

  # --- Hub-ros tunnel facts (RouterOS <-> hub). subnet_cidr only. ---
  # Null when routeros_enabled=false (var.hub_ros may then be null); every
  # consumer is count-gated on routeros_enabled.
  hub_ros_facts = var.routeros_enabled ? {
    subnet_cidr = "${cidrhost(var.hub_ros.hub_cidr, 0)}/${split("/", var.hub_ros.hub_cidr)[1]}"
  } : null

  # --- Firezone workload facts. ---
  firezone_facts = {
    directory      = "/opt/garuda/firezone"
    admin_email    = var.firezone_admin_email
    admin_password = var.firezone_admin_password
    client_subnet  = var.firezone_client_subnet
  }

  # --- Host LANs (var.host_lans). ---
  # FRR Tier 2 snippet per owner pod: static route to the LAN via the border gateway (the node) and
  # var.host_lan_alias on border, so the node can route the Firezone client subnet back to a stable
  # address. The alias is outside border_subnet: host-local IPAM never allocates it.
  host_lan_configmap = "frr-host-lan"
  host_lan_alias     = "${var.host_lan_alias}/32"
  host_lan_frr = {
    for k, lan in var.host_lans : k => {
      redistribute        = "static"
      frr_extra_configmap = local.host_lan_configmap
      configmaps = {
        (local.host_lan_configmap) = {
          "host-lan.conf" = templatefile("${path.module}/templates/host-lan.conf.tftpl", {
            lan   = lan
            gw    = cidrhost(var.border_subnet, 1)
            alias = local.host_lan_alias
          })
        }
      }
    }
  }
  host_lan_frr_none = { redistribute = "", frr_extra_configmap = "", configmaps = {} }

  # --- ipt_server pinning_egress: one entry per edge + the local border. ---
  # gw = peer address for edges; gw = border_router router-id for local egress.
  pinning_egress = merge(
    { for k, e in var.edges : k => { gw = split("/", e.peer_cidr)[0] } },
    { border = { gw = var.border_router.router_id } },
  )

  # --- Route groups (roles): primary -> fallback. ---
  # A role is an edge key or "border". The default egress order follows
  # var.edges iteration (lexicographic by key): de -> pt -> border. The
  # last-resort fallback and the RU group both target border_router via
  # gw=<router_id> (was dev=border, which used a gateway-less nexthop and dropped
  # off-link RU destinations — see the spec Problem section).
  default_route_groups = [
    {
      egress = concat(keys(var.edges), ["border"])
      rules = concat(
        [
          ".*",
          "0.0.0.0/0",
        ],
        var.ipt_routes_germany_nets,
      )
    },
    {
      egress = ["border"]
      rules = [
        "RU",
        ".*\\.ru",
      ]
    },
  ]

  ipt_route_groups_effective = var.ipt_route_groups != null ? var.ipt_route_groups : local.default_route_groups

  # role -> next-hop: edge peer address, or the border_router router-id.
  role_gw = merge(
    { for k, e in var.edges : k => split("/", e.peer_cidr)[0] },
    { border = var.border_router.router_id },
  )

  # --- ipt_routes: role groups resolved to gateways for ipt_server. ---
  ipt_routes = [
    for g in local.ipt_route_groups_effective : {
      route = [for r in g.egress : { gw = local.role_gw[r] }]
      rules = g.rules
    }
  ]

  # --- Firezone OIDC providers: empty map disables OIDC entirely. ---
  # One-element-list for-expression: the client id/secret (null when OIDC is
  # off) are only touched when enabled, and no conditional type unification.
  firezone_oidc_providers = {
    for k in(var.firezone_oidc_enabled ? ["google"] : []) : k => {
      client_id     = var.firezone_oidc_google_client_id
      client_secret = var.firezone_oidc_google_client_secret
      label         = "Google"
    }
  }

  # --- Tunnel state -> per-node materialized kubeconfig paths ---
  # garuda-tunnel runs `kube_targets` with `daemon.materialize=true`
  # and writes one patched kubeconfig per node-target to
  # <session_dir>/tunnel-data/<node>-<target>. The path is reported in
  # connections[node].kube_targets.k3s.path. Consumer reads only the
  # path string; server/CA/cert/key/tls-server-name live inside the
  # materialized file.
  #
  # Output shape: see https://github.com/garuda-tunnel/garuda-tunnel README
  # "Output reference" + design spec docs/superpowers/specs/
  # 2026-05-30-garuda-tunnel-kube-targets-migration-design.md.
  #
  # Empty branches: var.tunnel_path == "" (tofu test) or the JSON has
  # no connections entry (mock-state, host == 0.0.0.0). Both produce
  # "" via try(), and providers.tf takes the explicit inert branch.
  tunnel = jsondecode(var.tunnel_path == "" ? "{\"connections\":{}}" : file(var.tunnel_path))

  edges_kubeconfig_path = {
    for k in keys(var.edges) :
    k => try(local.tunnel.connections[k].kube_targets.k3s.path, "")
  }

  hub_kubeconfig_path = try(local.tunnel.connections.hub.kube_targets.k3s.path, "")
}
