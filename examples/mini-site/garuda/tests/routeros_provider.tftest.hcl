# Exercises the real routeros provider configure path. Do not mock routeros:
# count=0 resources still make OpenTofu configure this provider.
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
    host     = "192.0.2.1", user = "operator", connection = "ssh", network_os = "linux",
    password = null, ssh_private_key_file = null, ssh_private_key = null, instance_token = "mock-hub",
  }
  connection_data_edges = {}
  cloudflare_hub        = { zone_id = "fixture-zone", record_name = "hub.example.net" }
  cloudflare_edges      = {}

  routeros_enabled     = false
  routeros             = null
  routeros_password    = null
  hub_ros              = null
  routeros_lan_gateway = null

  remnawave_enabled     = false
  firezone_oidc_enabled = false
  ospf_router_ids       = { firezone = "198.51.100.22", ipt_server = "198.51.100.99" }

  backbone_subnet         = "192.0.2.0/26"
  border_subnet           = "192.0.2.64/26"
  firezone_client_subnet  = "198.51.100.128/25"
  hub_fqdn_prefix         = "hub"
  base_domain             = "example.net"
  edges                   = {}
  border_router           = { router_id = "198.51.100.50" }
  ipt_routes_germany_nets = []

  firezone_admin_password            = "test-password"
  firezone_oidc_google_client_id     = null
  firezone_oidc_google_client_secret = null
}

# A switch back to the API placeholder causes provider configuration to dial and
# fail. The REST placeholder with routeros_version must plan without I/O.
run "routeros_disabled_configures_without_dialing" {
  command = plan

  assert {
    condition     = length(routeros_ip_route.hub_ros_bypass_default) == 0
    error_message = "RouterOS resources must remain absent when RouterOS is disabled"
  }
}
