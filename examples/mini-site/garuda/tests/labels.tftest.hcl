# Validates label wiring and OSPF router-id propagation.

mock_provider "routeros" {}
mock_provider "wireguard" {}
mock_provider "local" {}
mock_provider "tls" {}
mock_provider "dns" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "helm" { alias = "pt" }
mock_provider "kubernetes" { alias = "pt" }
mock_provider "helm" { alias = "de" }
mock_provider "kubernetes" { alias = "de" }
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
    firezone   = "198.51.100.22"
    ipt_server = "198.51.100.99"
  }

  border_router = {
    router_id = "198.51.100.50"
  }

  ipt_routes_germany_nets = ["203.0.113.0/26", "203.0.113.64/26"]

  firezone_admin_password            = "test-password"
  firezone_oidc_google_client_id     = "test-id"
  firezone_oidc_google_client_secret = "test-secret"

  smoke_client_firezone = {
    inventory_name  = "fz-client-example"
    management_host = "203.0.113.200"
    user            = "operator"
  }
}

run "ipt_server_garuda_guest_router_id" {
  command = plan

  # OSPF intent now flows through garuda_guest, not legacy ipt_server_kube_ospf local.
  assert {
    condition     = module.garuda_guest_ipt_server_kube.annotations["net.garuda-tunnel/router-id"] == var.ospf_router_ids.ipt_server
    error_message = "ipt_server garuda_guest must emit router-id from var.ospf_router_ids.ipt_server"
  }
}

run "pt_default_originate_via_garuda_guest" {
  command = plan

  # Prod ground truth (2026-06-25-vxxlcx-prod-frr-ground-truth.md Q4): edge WireGuard
  # workloads do NOT originate a default route — ONLY ipt-server (transit-provider) does.
  # Neither the hub side nor the edge side of pt emits a default-originate annotation.
  assert {
    condition     = !contains(keys(module.garuda_guest_wireguard_kube_hub["pt"].annotations), "net.garuda-tunnel/default-originate")
    error_message = "pt hub-side garuda_guest must NOT emit default-originate annotation (profile default)"
  }

  assert {
    condition     = !contains(keys(module.garuda_guest_wireguard_kube_pt.annotations), "net.garuda-tunnel/default-originate")
    error_message = "pt edge-side garuda_guest must NOT emit default-originate (prod: only ipt-server originates the default)"
  }
}

run "firezone_runtime_wiring" {
  # A passing plan proves the reference graph is valid and types are compatible.
  command = plan
}
