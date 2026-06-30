locals {
  # --- Ansible inventory host names (transient, derived from env_slug). ---
  # hub: fixed key; edges: keyed by edge slug.
  host_names = merge(
    { hub = "hub-${var.env_slug}" },
    { for k, _ in var.edges : k => "${k}-${var.env_slug}" }
  )

  # --- Firezone FQDN derived from hub_fqdn_prefix + base_domain. ---
  firezone_fqdn = "${var.hub_fqdn_prefix}.${var.base_domain}"

  # --- Tunnel facts: one entry per edge (from var.edges map). ---
  # hub-side: hub_cidr, ospf_router_id_hub
  # edge-side: peer_cidr, ospf_router_id_peer
  tunnel_facts = {
    for k, e in var.edges : k => {
      subnet_cidr = "${cidrhost(e.hub_cidr, 0)}/${split("/", e.hub_cidr)[1]}"
      peers = {
        hub  = { cidr = e.hub_cidr, listen_port = e.listen_port }
        edge = { cidr = e.peer_cidr, listen_port = e.listen_port }
      }
    }
  }

  wireguard_kube_inputs = {
    for k, e in var.edges : k => {
      config = {
        kernel_ifname = module.wireguard_tunnel[k].peers["edge"].kernel_ifname
        private_key   = module.wireguard_tunnel[k].peers["edge"].private_key
        address       = module.wireguard_tunnel[k].peers["edge"].address
        subnet        = local.tunnel_facts[k].subnet_cidr
        listen_port   = module.wireguard_tunnel[k].peers["edge"].listen_port
        endpoint_host = module.wireguard_tunnel[k].peers["edge"].endpoint_host
      }
      peer = {
        public_key           = module.wireguard_tunnel[k].peers["core"].public_key
        endpoint_host        = module.wireguard_tunnel[k].peers["core"].endpoint_host
        endpoint_listen_port = module.wireguard_tunnel[k].peers["core"].listen_port
        preshared_key        = module.wireguard_tunnel[k].peers["core"].preshared_key
        address              = module.wireguard_tunnel[k].peers["core"].address
      }
      allowed_nets = ["0.0.0.0/0", "224.0.0.0/4"]
    }
  }

  # --- Hub-ros tunnel facts (RouterOS ↔ hub). ---
  hub_ros_facts = {
    subnet_cidr = "${cidrhost(var.hub_ros.hub_cidr, 0)}/${split("/", var.hub_ros.hub_cidr)[1]}"
    peers = {
      hub      = { cidr = var.hub_ros.hub_cidr, listen_port = var.hub_ros.listen_port }
      routeros = { cidr = var.hub_ros.routeros_cidr, listen_port = var.hub_ros.listen_port }
    }
  }

  # --- Firezone workload facts. ---
  firezone_facts = {
    directory      = "/opt/garuda/firezone"
    server_url     = "https://${local.firezone_fqdn}"
    admin_email    = var.firezone_admin_email
    admin_password = var.firezone_admin_password
    client_subnet  = var.firezone_client_subnet
  }

  # --- ipt_server facts. ---
  ipt_server_facts = {
    directory     = "/opt/garuda/ipt_server"
    frr_router_id = var.ospf_router_ids.ipt_server
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

  # --- Hub-side WireGuard kube inputs (per-edge tunnel core side). ---
  wireguard_kube_hub_inputs = {
    for k, e in var.edges : k => {
      config = {
        kernel_ifname = module.wireguard_tunnel[k].peers["core"].kernel_ifname
        private_key   = module.wireguard_tunnel[k].peers["core"].private_key
        address       = module.wireguard_tunnel[k].peers["core"].address
        subnet        = local.tunnel_facts[k].subnet_cidr
        listen_port   = module.wireguard_tunnel[k].peers["core"].listen_port
        endpoint_host = module.wireguard_tunnel[k].peers["core"].endpoint_host
      }
      peer = {
        public_key           = module.wireguard_tunnel[k].peers["edge"].public_key
        endpoint_host        = module.wireguard_tunnel[k].peers["edge"].endpoint_host
        endpoint_listen_port = module.wireguard_tunnel[k].peers["edge"].listen_port
        preshared_key        = module.wireguard_tunnel[k].peers["edge"].preshared_key
        address              = module.wireguard_tunnel[k].peers["edge"].address
      }
      allowed_nets = ["0.0.0.0/0", "224.0.0.0/4"]
    }
  }

  # --- Hub-side WireGuard kube inputs for RouterOS tunnel ---
  wireguard_kube_hub_ros_inputs = {
    config = {
      kernel_ifname = module.wireguard_tunnel_hub_ros.peers["core"].kernel_ifname
      private_key   = module.wireguard_tunnel_hub_ros.peers["core"].private_key
      address       = module.wireguard_tunnel_hub_ros.peers["core"].address
      subnet        = local.hub_ros_facts.subnet_cidr
      listen_port   = module.wireguard_tunnel_hub_ros.peers["core"].listen_port
      endpoint_host = module.wireguard_tunnel_hub_ros.peers["core"].endpoint_host
    }
    peer = {
      public_key           = module.wireguard_tunnel_hub_ros.peers["edge"].public_key
      endpoint_host        = module.wireguard_tunnel_hub_ros.peers["edge"].endpoint_host
      endpoint_listen_port = module.wireguard_tunnel_hub_ros.peers["edge"].listen_port
      preshared_key        = module.wireguard_tunnel_hub_ros.peers["edge"].preshared_key
      address              = module.wireguard_tunnel_hub_ros.peers["edge"].address
    }
    allowed_nets = ["0.0.0.0/0", "224.0.0.0/4"]
  }
}
