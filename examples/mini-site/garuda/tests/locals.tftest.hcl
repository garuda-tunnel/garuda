# Validates computed locals in garuda/ module.
# Covers ipt_routes, tunnel_facts, firezone_facts.

mock_provider "routeros" {}
mock_provider "wireguard" {}
mock_provider "tls" {}
mock_provider "dns" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "helm" {
  alias    = "edge"
  for_each = var.edges
}
mock_provider "kubernetes" {
  alias    = "edge"
  for_each = var.edges
}
mock_provider "helm" { alias = "hub" }
mock_provider "kubernetes" { alias = "hub" }

variables {
  env_slug = "mini-site"

  connection_data_hub = {
    host           = "192.0.2.1", user = "operator", connection = "ssh", network_os = "linux",
    password       = null, ssh_private_key_file = null, ssh_private_key = null,
    instance_token = "mock-hub",
  }

  connection_data_edges = {
    pt = {
      host           = "192.0.2.2", user = "operator", connection = "ssh", network_os = "linux",
      password       = null, ssh_private_key_file = null, ssh_private_key = null,
      instance_token = "mock-pt",
    }
    de = {
      host           = "192.0.2.3", user = "operator", connection = "ssh", network_os = "linux",
      password       = null, ssh_private_key_file = null, ssh_private_key = null,
      instance_token = "mock-de",
    }
  }

  cloudflare_hub = { zone_id = "fixture-zone", record_name = "hub.example.net" }
  cloudflare_edges = {
    pt = { zone_id = "fixture-zone", record_name = "pt.example.net" }
    de = { zone_id = "fixture-zone", record_name = "de.example.net" }
  }

  routeros = {
    hostname = "routeros-example", management_host = "203.0.113.1",
    user     = "admin", uplink_interface = "ether1"
  }
  routeros_password    = "admin"
  routeros_lan_gateway = "203.0.113.1"

  backbone_subnet        = "192.0.2.0/26"
  border_subnet          = "192.0.2.64/26"
  firezone_client_subnet = "198.51.100.128/25"

  hub_fqdn_prefix = "hub"
  base_domain     = "example.net"

  edges = {
    pt = {
      machine_type        = "e2-small"
      boot_disk_gb        = 20
      region              = "us-central1"
      zone                = "us-central1-a"
      fqdn_prefix         = "pt"
      hub_cidr            = "192.0.2.129/28"
      peer_cidr           = "192.0.2.130/28"
      listen_port         = 51820
      ospf_router_id_hub  = "198.51.100.20"
      ospf_router_id_peer = "198.51.100.23"
    }
    de = {
      machine_type        = "e2-small"
      boot_disk_gb        = 20
      region              = "europe-west3"
      zone                = "europe-west3-a"
      fqdn_prefix         = "de"
      hub_cidr            = "192.0.2.145/28"
      peer_cidr           = "192.0.2.146/28"
      listen_port         = 51821
      ospf_router_id_hub  = "198.51.100.30"
      ospf_router_id_peer = "198.51.100.33"
    }
  }

  hub_ros = {
    hub_cidr           = "192.0.2.161/28"
    routeros_cidr      = "192.0.2.162/28"
    listen_port        = 51822
    ospf_router_id_hub = "198.51.100.21"
  }

  ospf_router_ids = {
    firezone       = "198.51.100.22"
    ipt_server     = "198.51.100.99"
    remnawave_node = "10.130.30.45"
  }

  border_router = {
    router_id = "198.51.100.50"
  }

  ipt_routes_germany_nets = ["203.0.113.0/26", "203.0.113.64/26"]

  firezone_admin_password            = "test-password"
  firezone_oidc_google_client_id     = "test-id"
  firezone_oidc_google_client_secret = "test-secret"


  tunnel_path = "tests/fixtures/tunnel-state-hub-pt-de.json"
}

run "tunnel_facts_structure" {
  command = plan

  assert {
    condition     = length(keys(local.tunnel_facts)) == 2
    error_message = "tunnel_facts must have 2 entries (pt + de)"
  }

  assert {
    condition = (
      contains(keys(local.tunnel_facts), "pt") &&
      contains(keys(local.tunnel_facts), "de")
    )
    error_message = "tunnel_facts keys must be pt and de"
  }

  assert {
    condition     = local.tunnel_facts.pt.subnet_cidr == "192.0.2.128/28"
    error_message = "tunnel_facts[pt].subnet_cidr must be the /28 network of hub_cidr 192.0.2.129/28"
  }
}

run "edge_wireguard_self_is_edge_peer" {
  command = plan

  assert {
    condition     = module.wireguard_kube_edge["pt"].deployment_name == "wg-pt"
    error_message = "pt edge wireguard deployment must be wg-pt (self=edge peer)"
  }

  assert {
    condition     = module.wireguard_kube_edge["de"].deployment_name == "wg-de"
    error_message = "de edge wireguard deployment must be wg-de (self=edge peer)"
  }
}

run "garuda_guest_edge_wg_intent" {
  command = plan

  # OSPF intent now lives in garuda_guest modules; validate annotations emitted.
  assert {
    condition     = module.garuda_guest_wireguard_kube_edge["pt"].annotations["net.garuda-tunnel/router-id"] == var.edges["pt"].ospf_router_id_peer
    error_message = "pt edge garuda_guest must emit router-id annotation from ospf_router_id_peer"
  }

  assert {
    condition     = module.garuda_guest_wireguard_kube_edge["de"].annotations["net.garuda-tunnel/router-id"] == var.edges["de"].ospf_router_id_peer
    error_message = "de edge garuda_guest must emit router-id annotation from ospf_router_id_peer"
  }

  assert {
    condition     = !contains(keys(module.garuda_guest_wireguard_kube_edge["pt"].annotations), "net.garuda-tunnel/default-originate")
    error_message = "pt edge garuda_guest must NOT emit default-originate (prod: only ipt-server originates the default)"
  }

  assert {
    condition     = module.garuda_guest_wireguard_kube_edge["pt"].labels["net.garuda-tunnel/profile"] == "ospf-router"
    error_message = "pt edge garuda_guest must emit profile=ospf-router label"
  }
}

run "ipt_routes_two_entries" {
  command = plan

  assert {
    condition     = length(local.ipt_routes) == 2
    error_message = "ipt_routes must have exactly two action groups"
  }

  assert {
    condition     = length(local.ipt_routes[0].route) == 3
    error_message = "default action group must have three route members (de gw, pt gw, border gw)"
  }

  assert {
    # Terraform maps iterate in lexicographic key order: de < pt.
    condition = (
      local.ipt_routes[0].route[0].gw == "192.0.2.146" &&
      local.ipt_routes[0].route[1].gw == "192.0.2.130" &&
      local.ipt_routes[0].route[2].gw == "198.51.100.50"
    )
    error_message = "route order must be de gw -> pt gw -> border gw (lexicographic map iteration)"
  }
}

run "ipt_routes_use_border_router_gw" {
  command = plan

  # RU group and non-RU fallback must target gw=<router_id>, not dev=border.
  assert {
    condition     = strcontains(jsonencode(local.ipt_routes), "\"gw\":\"198.51.100.50\"")
    error_message = "ipt_routes must route to border_router via gw=<router_id>"
  }

  assert {
    condition     = !strcontains(jsonencode(local.ipt_routes), "\"dev\":\"border\"")
    error_message = "ipt_routes must not use dev=border (gateway-less nexthop bug)"
  }
}

run "pinning_egress_includes_border" {
  command = plan

  assert {
    condition     = local.pinning_egress["border"].gw == "198.51.100.50"
    error_message = "pinning_egress must expose a border entry gw=<router_id>"
  }
}

run "firezone_facts_directory" {
  command = plan

  # server_url was dropped from firezone_facts (dead: firezone_kube consumes
  # local.firezone_fqdn directly via server_fqdn). directory remains referenced.
  assert {
    condition     = local.firezone_facts.directory == "/opt/garuda/firezone"
    error_message = "firezone directory must be /opt/garuda/firezone"
  }
}

run "regression_catchall_domain_in_ipt_routes" {
  command = plan

  assert {
    condition     = output.ipt_routes_count > 0
    error_message = "ipt_routes must not be empty"
  }
}

run "hub_tunnel_kubeconfig_path_contract" {
  command = plan

  assert {
    condition     = local.hub_kubeconfig_path == "/var/tmp/garuda-tunnel-fixture/tunnel-data/hub-k3s"
    error_message = "hub_kubeconfig_path must be the materialized file path from local.tunnel.connections.hub.kube_targets.k3s.path"
  }

  assert {
    condition = (
      local.edges_kubeconfig_path["pt"] == "/var/tmp/garuda-tunnel-fixture/tunnel-data/pt-k3s" &&
      local.edges_kubeconfig_path["de"] == "/var/tmp/garuda-tunnel-fixture/tunnel-data/de-k3s"
    )
    error_message = "edges_kubeconfig_path[pt|de] must be the materialized file paths from local.tunnel.connections.<edge>.kube_targets.k3s.path"
  }
}

run "garuda_guest_hub_wg_intent" {
  command = plan

  # Hub-side WireGuard OSPF intent now lives in garuda_guest modules.
  assert {
    condition     = module.garuda_guest_wireguard_kube_hub["pt"].annotations["net.garuda-tunnel/router-id"] == var.edges["pt"].ospf_router_id_hub
    error_message = "hub-side wg pt garuda_guest must emit router-id from ospf_router_id_hub"
  }

  assert {
    condition     = module.garuda_guest_wireguard_kube_hub["de"].annotations["net.garuda-tunnel/router-id"] == var.edges["de"].ospf_router_id_hub
    error_message = "hub-side wg de garuda_guest must emit router-id from ospf_router_id_hub"
  }
}

run "garuda_guest_hub_workloads_intent" {
  command = plan

  assert {
    condition     = module.garuda_guest_firezone_kube.annotations["net.garuda-tunnel/router-id"] == var.ospf_router_ids.firezone
    error_message = "firezone garuda_guest must emit router-id from var.ospf_router_ids.firezone"
  }

  assert {
    condition     = module.garuda_guest_firezone_kube.annotations["net.garuda-tunnel/passive-interfaces"] == "wg-firezone"
    error_message = "firezone garuda_guest must emit passive-interfaces=wg-firezone (prod: wg-firezone is OSPF-passive)"
  }

  assert {
    condition     = module.garuda_guest_ipt_server_kube.annotations["net.garuda-tunnel/router-id"] == var.ospf_router_ids.ipt_server
    error_message = "ipt_server garuda_guest must emit router-id from var.ospf_router_ids.ipt_server"
  }

  assert {
    condition     = module.garuda_guest_ipt_server_kube.labels["net.garuda-tunnel/profile"] == "transit-provider"
    error_message = "ipt_server garuda_guest must emit profile=transit-provider label"
  }

  assert {
    condition     = module.garuda_guest_border_router.labels["net.garuda-tunnel/profile"] == "border"
    error_message = "border_router garuda_guest must emit profile=border label"
  }
}
