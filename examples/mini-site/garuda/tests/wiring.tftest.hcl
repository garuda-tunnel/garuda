# Validates that the smoke inventory is correctly wired from connection_data.

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

run "smoke_inventory_contains_all_hosts" {
  command = plan

  assert {
    condition     = contains(keys(output.ansible_smoke_inventory), "hub")
    error_message = "smoke inventory must contain hub"
  }

  assert {
    condition     = contains(keys(output.ansible_smoke_inventory), "pt")
    error_message = "smoke inventory must contain pt"
  }

  assert {
    condition     = contains(keys(output.ansible_smoke_inventory), "de")
    error_message = "smoke inventory must contain de"
  }

  assert {
    condition     = contains(keys(output.ansible_smoke_inventory), "routeros")
    error_message = "smoke inventory must contain routeros"
  }
}

run "routeros_inventory_uses_connection_data" {
  command = plan

  assert {
    condition     = output.ansible_smoke_inventory.routeros.ansible_host == var.routeros.management_host
    error_message = "routeros inventory host must come from var.routeros.management_host"
  }

  assert {
    condition     = output.ansible_smoke_inventory.routeros.ansible_user == var.routeros.user
    error_message = "routeros inventory user must come from var.routeros.user"
  }
}

run "linux_inventory_uses_connection_data" {
  command = plan

  assert {
    condition     = output.ansible_smoke_inventory.hub.ansible_host == var.connection_data_hub.host
    error_message = "hub inventory host must come from var.connection_data_hub.host"
  }

  assert {
    condition     = output.ansible_smoke_inventory.pt.ansible_host == var.connection_data_edges.pt.host
    error_message = "pt inventory host must come from var.connection_data_edges.pt.host"
  }

  assert {
    condition     = output.ansible_smoke_inventory.de.ansible_host == var.connection_data_edges.de.host
    error_message = "de inventory host must come from var.connection_data_edges.de.host"
  }
}

run "edge_k3s_modules_are_wired" {
  command = plan

  assert {
    condition     = module.garuda_k8s_pt.namespace == "garuda"
    error_message = "pt Kubernetes bootstrap must create/use namespace garuda"
  }

  assert {
    condition     = module.garuda_k8s_de.namespace == "garuda"
    error_message = "de Kubernetes bootstrap must create/use namespace garuda"
  }

  assert {
    condition     = module.wireguard_kube_pt.deployment_name == "wg-pt"
    error_message = "pt Kubernetes WireGuard deployment must be wg-pt"
  }

  assert {
    condition     = module.wireguard_kube_de.deployment_name == "wg-de"
    error_message = "de Kubernetes WireGuard deployment must be wg-de"
  }
}

run "hub_k3s_modules_are_wired" {
  command = plan

  assert {
    condition     = module.garuda_k8s_hub.namespace == "garuda"
    error_message = "hub Kubernetes bootstrap must create/use namespace garuda"
  }

  assert {
    condition     = module.wireguard_kube_hub["pt"].deployment_name == "wg-pt"
    error_message = "hub-side wg pt deployment must be wg-pt"
  }

  assert {
    condition     = module.wireguard_kube_hub["de"].deployment_name == "wg-de"
    error_message = "hub-side wg de deployment must be wg-de"
  }

  assert {
    condition     = module.wireguard_kube_hub_ros.deployment_name == "wg-hub-ros"
    error_message = "hub-side RouterOS deployment must be wg-hub-ros"
  }

  assert {
    condition     = module.cert_manager.cluster_issuer_name == "letsencrypt-prod"
    error_message = "cert_manager module must expose letsencrypt-prod cluster issuer by default"
  }

  assert {
    condition     = module.k8s_gateway_bootstrap.gateway_name == "platform-gateway"
    error_message = "k8s_gateway_bootstrap must expose stable gateway name"
  }

  assert {
    condition     = module.k8s_gateway_bootstrap.gateway_namespace == "gateway-system"
    error_message = "k8s_gateway_bootstrap must live in gateway-system namespace"
  }

  # firezone_kube receives gateway_ref inline from k8s_gateway_bootstrap outputs (see main.tf).
  # module.firezone_kube does not re-expose gateway_ref, so the wiring contract is
  # validated by locking both k8s_gateway_bootstrap outputs above and confirming the
  # service URL is reachable under the same FQDN that the gateway routes.
  assert {
    condition     = module.firezone_kube.service_url == "https://${var.hub_fqdn_prefix}.${var.base_domain}"
    error_message = "firezone_kube service_url must match the hub FQDN routed by platform-gateway (gateway_ref wiring contract)"
  }

  assert {
    condition     = module.firezone_kube.deployment_name == "firezone"
    error_message = "firezone_kube deployment must be firezone"
  }

  assert {
    condition     = module.ipt_server_kube.deployment_name == "ipt-server"
    error_message = "ipt_server_kube deployment must be ipt-server"
  }
}

run "border_router_module_is_wired" {
  command = plan

  assert {
    condition     = module.border_router.deployment_name == "border-router"
    error_message = "border_router module must be wired and named border-router"
  }
}

run "tunnel_path_empty_yields_inert_kubeconfig_paths" {
  command = plan

  assert {
    condition     = local.hub_kubeconfig_path == ""
    error_message = "hub_kubeconfig_path must be \"\" when var.tunnel_path is unset (mock-state / tofu test path)"
  }

  assert {
    condition = (
      local.edges_kubeconfig_path["pt"] == "" &&
      local.edges_kubeconfig_path["de"] == ""
    )
    error_message = "edges_kubeconfig_path[pt|de] must be \"\" when var.tunnel_path is unset"
  }
}
