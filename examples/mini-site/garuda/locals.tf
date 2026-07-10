locals {
  # --- Ansible inventory host names (transient, derived from env_slug). ---
  # hub: fixed key; edges: keyed by edge slug.
  host_names = merge(
    { hub = "hub-${var.env_slug}" },
    { for k, _ in var.edges : k => "${k}-${var.env_slug}" }
  )

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
  hub_ros_facts = {
    subnet_cidr = "${cidrhost(var.hub_ros.hub_cidr, 0)}/${split("/", var.hub_ros.hub_cidr)[1]}"
  }

  # --- Firezone workload facts. ---
  firezone_facts = {
    directory      = "/opt/garuda/firezone"
    admin_email    = var.firezone_admin_email
    admin_password = var.firezone_admin_password
    client_subnet  = var.firezone_client_subnet
  }

  # --- ipt_server pinning_egress: one entry per edge + the local border. ---
  # gw = peer address for edges; gw = border_router router-id for local egress.
  pinning_egress = merge(
    { for k, e in var.edges : k => { gw = split("/", e.peer_cidr)[0] } },
    { border = { gw = var.border_router.router_id } },
  )

  # --- ipt_routes: primary -> fallback. ---
  # Egress order derived from var.edges iteration (lexicographic by key): de -> pt.
  # The last-resort fallback and the RU group both target border_router via
  # gw=<router_id> (was dev=border, which used a gateway-less nexthop and dropped
  # off-link RU destinations — see the spec Problem section).
  ipt_routes = [
    {
      route = concat(
        [for k, e in var.edges : { gw = split("/", e.peer_cidr)[0] }],
        [{ gw = var.border_router.router_id }],
      )
      rules = concat(
        [
          ".*",
          "0.0.0.0/0",
        ],
        var.ipt_routes_germany_nets,
      )
    },
    {
      route = [{ gw = var.border_router.router_id }]
      rules = [
        "RU",
        ".*\\.ru",
      ]
    },
  ]

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
