# Validates the stand opt-out flags (routeros/remnawave/firezone oidc), route
# groups and that cloud defaults keep today's resource addresses and values.

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

}

run "defaults_unchanged" {
  command = plan

  # Today's default group-0 egress order: edges (lexicographic) then border.
  assert {
    condition     = output.ipt_routes_primary_gws == ["192.0.2.146", "192.0.2.130", "198.51.100.50"]
    error_message = "default primary gws must be de, pt peers then the border router-id"
  }

  assert {
    condition     = output.ipt_routes_count == 2
    error_message = "default ipt_routes must keep two groups"
  }

  # Gated resources keep existing addresses (moved blocks map them to [0]).
  assert {
    condition     = routeros_ip_route.hub_ros_bypass_default[0].gateway == var.routeros_lan_gateway
    error_message = "RouterOS bypass route must be planned by default"
  }

  assert {
    condition     = routeros_ip_firewall_nat.hub_ros_masquerade[0].out_interface == var.routeros.uplink_interface
    error_message = "RouterOS masquerade must be planned by default"
  }

  assert {
    condition     = module.remnawave_panel[0].node_ospf_router_id == var.ospf_router_ids.remnawave_node
    error_message = "remnawave_panel must be planned by default"
  }

  assert {
    condition     = module.wireguard_kube_hub_ros[0].deployment_name == "wg-hub-ros"
    error_message = "hub-ros workload must be planned by default"
  }

  assert {
    condition     = length(local.firezone_oidc_providers) == 1
    error_message = "google OIDC provider must be configured by default"
  }

  assert {
    condition     = jsonencode([for g in output.ipt_route_groups_egress : g.egress]) == jsonencode([["de", "pt", "border"], ["border"]])
    error_message = "default route groups must be reported as roles"
  }
}

run "stand_flags_off" {
  command = plan

  variables {
    routeros_enabled      = false
    remnawave_enabled     = false
    firezone_oidc_enabled = false

    routeros                           = null
    routeros_password                  = null
    hub_ros                            = null
    routeros_lan_gateway               = null
    firezone_oidc_google_client_id     = null
    firezone_oidc_google_client_secret = null
    ospf_router_ids = {
      firezone   = "198.51.100.22"
      ipt_server = "198.51.100.99"
    }
  }

  assert {
    condition     = length(routeros_ip_route.hub_ros_bypass_default) == 0 && length(routeros_ip_firewall_nat.hub_ros_masquerade) == 0
    error_message = "RouterOS resources must not be planned when routeros_enabled=false"
  }

  assert {
    condition     = length(module.wireguard_routeros_hub_ros) == 0 && length(module.wireguard_tunnel_hub_ros) == 0 && length(module.wireguard_kube_hub_ros) == 0
    error_message = "hub-ros tunnel modules must not be planned when routeros_enabled=false"
  }

  assert {
    condition     = length(module.remnawave_panel) == 0 && length(module.garuda_guest_remnawave_node) == 0
    error_message = "Remnawave modules must not be planned when remnawave_enabled=false"
  }

  assert {
    condition     = output.remnawave_node_ospf_router_id == null
    error_message = "remnawave outputs must be null when disabled"
  }

  assert {
    condition     = length(local.firezone_oidc_providers) == 0
    error_message = "OIDC provider map must be empty when firezone_oidc_enabled=false"
  }
}

run "routeros_inputs_required_when_enabled" {
  command = plan

  variables {
    routeros = null
  }

  expect_failures = [var.routeros]
}

run "route_groups_twin" {
  command = plan

  variables {
    edges = {
      out1 = {
        machine_type       = "e2-small", boot_disk_gb = 20, region = "r", zone = "z", fqdn_prefix = "out1",
        hub_cidr           = "192.0.2.129/28", peer_cidr = "192.0.2.130/28", listen_port = 51820,
        ospf_router_id_hub = "198.51.100.20", ospf_router_id_peer = "198.51.100.23"
      }
      out2 = {
        machine_type       = "e2-small", boot_disk_gb = 20, region = "r", zone = "z", fqdn_prefix = "out2",
        hub_cidr           = "192.0.2.145/28", peer_cidr = "192.0.2.146/28", listen_port = 51821,
        ospf_router_id_hub = "198.51.100.30", ospf_router_id_peer = "198.51.100.33"
      }
    }
    connection_data_edges = {
      out1 = {
        host     = "192.0.2.2", user = "operator", connection = "ssh", network_os = "linux",
        password = null, ssh_private_key_file = null, ssh_private_key = null, instance_token = "m1",
      }
      out2 = {
        host     = "192.0.2.3", user = "operator", connection = "ssh", network_os = "linux",
        password = null, ssh_private_key_file = null, ssh_private_key = null, instance_token = "m2",
      }
    }
    cloudflare_edges = {
      out1 = { zone_id = "z", record_name = "out1.example.net" }
      out2 = { zone_id = "z", record_name = "out2.example.net" }
    }
    ipt_route_groups = [
      { egress = ["out1", "out2", "border"], rules = ["203.0.113.138/32"] },
      { egress = ["out2", "out1", "border"], rules = ["203.0.113.139/32"] },
    ]
  }

  assert {
    condition     = jsonencode([for g in output.ipt_route_groups_egress : g.egress]) == jsonencode([["out1", "out2", "border"], ["out2", "out1", "border"]])
    error_message = "route group egress roles must be reported as given"
  }

  assert {
    condition     = [for m in local.ipt_routes[0].route : m.gw] == ["192.0.2.130", "192.0.2.146", "198.51.100.50"]
    error_message = "group 0 gws must follow out1, out2, border order"
  }

  assert {
    condition     = [for m in local.ipt_routes[1].route : m.gw] == ["192.0.2.146", "192.0.2.130", "198.51.100.50"]
    error_message = "group 1 gws must follow out2, out1, border order"
  }

  assert {
    condition     = jsonencode(local.ipt_routes[1].rules) == jsonencode(["203.0.113.139/32"])
    error_message = "group rules must be passed through"
  }
}

run "route_groups_bad_role" {
  command = plan

  variables {
    ipt_route_groups = [{ egress = ["nope"], rules = [".*"] }]
  }

  expect_failures = [var.ipt_route_groups]
}

run "route_groups_require_egress" {
  command = plan

  variables {
    ipt_route_groups = [{ egress = [], rules = [] }]
  }

  expect_failures = [var.ipt_route_groups]
}

run "route_groups_require_a_group" {
  command = plan

  variables {
    ipt_route_groups = []
  }

  expect_failures = [var.ipt_route_groups]
}

run "pod_reaper_max_unready_accepts_duration" {
  command = plan

  variables {
    pod_reaper_max_unready = "900s"
  }

  assert {
    condition     = module.garuda_k8s_hub.namespace == "garuda" && module.garuda_k8s["pt"].namespace == "garuda"
    error_message = "a pod reaper override must plan the hub and edge garuda modules unchanged"
  }
}

run "host_lans_default_empty" {
  command = plan

  # Empty host_lans must add no intent annotation and no ConfigMap anywhere.
  assert {
    condition = alltrue([
      for k in ["pt", "de"] : !contains(keys(module.garuda_guest_wireguard_kube_edge[k].annotations), "net.garuda-tunnel/redistribute")
      && !contains(keys(module.garuda_guest_wireguard_kube_edge[k].annotations), "net.garuda-tunnel/frr-extra-configmap")
      && length(module.garuda_guest_wireguard_kube_edge[k].configmaps) == 0
    ])
    error_message = "default edge guests must carry no host LAN intent"
  }

  assert {
    condition = (
      !contains(keys(module.garuda_guest_border_router.annotations), "net.garuda-tunnel/redistribute")
      && !contains(keys(module.garuda_guest_border_router.annotations), "net.garuda-tunnel/frr-extra-configmap")
      && length(module.garuda_guest_border_router.configmaps) == 0
    )
    error_message = "default border-router guest must carry no host LAN intent"
  }
}

run "host_lans_render" {
  command = plan

  variables {
    host_lans              = { hub = "10.210.0.0/24", pt = "10.211.0.0/24" }
    firezone_client_subnet = "10.213.0.0/24"
  }

  assert {
    condition = (
      module.garuda_guest_border_router.annotations["net.garuda-tunnel/redistribute"] == "static"
      && module.garuda_guest_border_router.annotations["net.garuda-tunnel/frr-extra-configmap"] == "frr-host-lan"
      && module.garuda_guest_wireguard_kube_edge["pt"].annotations["net.garuda-tunnel/redistribute"] == "static"
    )
    error_message = "hub and pt owner pods must redistribute static and mount the host LAN snippet"
  }

  assert {
    condition     = !contains(keys(module.garuda_guest_wireguard_kube_edge["de"].annotations), "net.garuda-tunnel/frr-extra-configmap")
    error_message = "an edge without a host LAN must stay untouched"
  }

  assert {
    condition = (
      strcontains(module.garuda_guest_border_router.configmaps["frr-host-lan"]["host-lan.conf"], "ip route 10.210.0.0/24 192.0.2.65\n")
      && strcontains(module.garuda_guest_wireguard_kube_edge["pt"].configmaps["frr-host-lan"]["host-lan.conf"], "ip route 10.211.0.0/24 192.0.2.65\n")
      && strcontains(module.garuda_guest_border_router.configmaps["frr-host-lan"]["host-lan.conf"], "ip address 169.254.1.1/32\n")
    )
    error_message = "snippet must hold the static route via the border gateway and the border alias"
  }
}

run "host_lans_reject_public_cidr" {
  command = plan

  variables {
    host_lans              = { hub = "203.0.113.0/24" }
    firezone_client_subnet = "10.213.0.0/24"
  }

  expect_failures = [var.host_lans]
}

# 10.0.0.0/7 and 192.168.0.0/15 only look private: RFC 1918 supersets that
# spill into public space are rejected like any other public CIDR.
run "host_lans_reject_lookalike_cidrs" {
  command = plan

  variables {
    host_lans              = { hub = "10.0.0.0/7", pt = "192.168.0.0/15" }
    firezone_client_subnet = "172.20.0.0/24"
  }

  expect_failures = [var.host_lans]
}

run "host_lans_reject_unknown_key" {
  command = plan

  variables {
    host_lans              = { nope = "10.210.0.0/24" }
    firezone_client_subnet = "10.213.0.0/24"
  }

  expect_failures = [var.host_lans]
}

run "host_lans_reject_overlap_with_client_subnet" {
  command = plan

  variables {
    host_lans              = { hub = "10.213.0.0/25" }
    firezone_client_subnet = "10.213.0.0/24"
  }

  expect_failures = [var.host_lans]
}

run "host_lans_reject_overlap_with_border" {
  command = plan

  variables {
    host_lans              = { hub = "192.168.0.0/16" }
    firezone_client_subnet = "10.213.0.0/24"
    border_subnet          = "192.168.7.0/24"
  }

  expect_failures = [var.host_lans]
}

run "host_lans_require_private_client_subnet" {
  command = plan

  # The fixture client subnet is 198.51.100.128/25 (not RFC 1918).
  variables {
    host_lans = { hub = "10.210.0.0/24" }
  }

  expect_failures = [var.host_lans]
}

run "host_lan_alias_must_stay_outside_border" {
  command = plan

  variables {
    host_lan_alias = "192.0.2.126"
  }

  expect_failures = [var.host_lan_alias]
}

run "host_lan_alias_must_be_an_address" {
  command = plan

  variables {
    host_lan_alias = "not-an-ip"
  }

  expect_failures = [var.host_lan_alias]
}

run "host_lan_alias_rejects_non_ipv4" {
  command = plan

  variables {
    host_lan_alias = "2001:db8::1"
  }

  expect_failures = [var.host_lan_alias]
}
