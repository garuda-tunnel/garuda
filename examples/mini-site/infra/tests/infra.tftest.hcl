# Tests for examples/mini-site/infra/ unit (Proxmox hub and client).
# Validates the Proxmox hub/client VMs, per-node k3s-bootstrap wiring,
# key-path-only connection bundles and Cloudflare DNS record scope.
# Uses mock providers — no real cloud credentials needed. The k3s-bootstrap
# module is overridden (its outputs are not consumed by this root).

mock_provider "proxmox" {}
mock_provider "google" {}
mock_provider "cloudflare" {}
mock_provider "routeros" {}
mock_provider "tls" {}
mock_provider "local" {}

override_module {
  target = module.k3s
  outputs = {
    head               = null
    kubeconfig_path    = null
    api_forward_target = null
  }
}

variables {
  env_slug = "mini-site"

  proxmox = {
    endpoint      = "https://pve.example.net:8006/"
    node_name     = "pve-node-example"
    pool_id       = "pool-example"
    datastore_id  = "storage-example"
    bridge        = "vmbr-example"
    image_file_id = "local:import/ubuntu-example.qcow2"
    gateway       = "203.0.113.1"
    dns_servers   = ["192.0.2.53", "198.51.100.53"]
    hub = {
      address   = "203.0.113.184"
      cores     = 2
      memory_mb = 4096
      disk_gb   = 40
    }
    client = {
      address   = "203.0.113.185"
      cores     = 1
      memory_mb = 2048
      disk_gb   = 20
    }
  }

  ssh_public_key_file  = "tests/ssh_public_key.pub"
  ssh_private_key_file = "tests/ssh_private_key"
  known_hosts_file     = "/tmp/mini-site-tests-known_hosts"

  k3s_version       = "v1.33.0+k3s1"
  cluster_cidrs     = ["10.42.0.0/16", "10.43.0.0/16"]
  api_trusted_cidrs = ["192.0.2.0/24", "198.51.100.0/24"]

  gcp = {
    project_id = "my-gcp-project"
  }
  gcp_credentials_json = "{}"

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

  cloudflare = {
    zone_name = "example.net"
  }
  cloudflare_api_token = "fixture"

  hub_fqdn_prefix = "hub"
  base_domain     = "example.net"

  routeros_enabled  = false
  routeros          = null
  routeros_password = null

  operator_ssh_keys = ["operator:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample operator@example"]
}

run "no_yandex" {
  # No yandex mock_provider is declared: a plan that succeeds here proves the
  # unit carries no yandex provider requirement (no YC resources remain).
  command = plan

  assert {
    condition     = length(keys(output.connection_data_edges)) == 2
    error_message = "connection_data_edges must carry exactly the two GCP edges"
  }
}

run "vms_in_pool" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.hub.pool_id == var.proxmox.pool_id
    error_message = "hub VM must live in var.proxmox.pool_id"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.client.pool_id == var.proxmox.pool_id
    error_message = "client VM must live in var.proxmox.pool_id"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.hub.agent[0].enabled == true
    error_message = "hub VM agent must be enabled"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.hub.agent[0].timeout == "10s"
    error_message = "hub VM agent timeout must be 10s so create does not wait for an agent that k3s-bootstrap installs only later"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.client.agent[0].enabled == true && proxmox_virtual_environment_vm.client.agent[0].timeout == "10s"
    error_message = "client VM agent must be enabled with the 10s timeout"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.hub.stop_on_destroy == true && proxmox_virtual_environment_vm.client.stop_on_destroy == true
    error_message = "both VMs must set stop_on_destroy"
  }
}

run "edges_image_is_ubuntu_2604" {
  command = plan

  assert {
    condition     = var.gcp_image == "projects/ubuntu-os-cloud/global/images/family/ubuntu-2604-lts-amd64"
    error_message = "gcp_image default must be the Ubuntu 26.04 LTS family (k3s-bootstrap v0.2.0 preflight asserts 26.04)"
  }

  assert {
    condition     = alltrue([for k in ["pt", "de"] : module.gcp_edges[k].test_boot_image == var.gcp_image])
    error_message = "every edge boot disk must use var.gcp_image"
  }
}

run "edges_reject_reserved_slug_hub" {
  command = plan

  variables {
    edges = {
      hub = {
        machine_type        = "e2-small"
        boot_disk_gb        = 20
        region              = "us-central1"
        zone                = "us-central1-a"
        fqdn_prefix         = "hub-edge"
        hub_cidr            = "192.0.2.161/28"
        peer_cidr           = "192.0.2.162/28"
        listen_port         = 51822
        ospf_router_id_hub  = "198.51.100.40"
        ospf_router_id_peer = "198.51.100.43"
      }
    }
  }

  expect_failures = [
    var.edges,
  ]
}

run "edges_reject_reserved_slug_client" {
  command = plan

  variables {
    edges = {
      client = {
        machine_type        = "e2-small"
        boot_disk_gb        = 20
        region              = "europe-west3"
        zone                = "europe-west3-a"
        fqdn_prefix         = "client-edge"
        hub_cidr            = "192.0.2.177/28"
        peer_cidr           = "192.0.2.178/28"
        listen_port         = 51823
        ospf_router_id_hub  = "198.51.100.50"
        ospf_router_id_peer = "198.51.100.53"
      }
    }
  }

  expect_failures = [
    var.edges,
  ]
}

run "bootstrap_per_node" {
  command = plan

  # Asserts the wiring map (local.k3s_nodes via output.test_k3s_bootstrap_nodes), not the arguments actually passed to module.k3s: OpenTofu tests cannot reference module call inputs.
  assert {
    condition     = length(keys(output.test_k3s_bootstrap_nodes)) == 3
    error_message = "exactly three k3s-bootstrap calls: hub + one per edge"
  }

  assert {
    condition     = !contains(keys(output.test_k3s_bootstrap_nodes), "client")
    error_message = "the test client must not be bootstrapped with k3s"
  }

  assert {
    condition     = length(terraform_data.known_hosts) == 4
    error_message = "known_hosts keyscan must cover hub, client and both edges"
  }

  assert {
    condition     = contains(keys(terraform_data.known_hosts), "client")
    error_message = "the client must be keyscanned too (trust-on-first-use for operator SSH)"
  }

  assert {
    condition     = output.test_k3s_bootstrap_nodes.hub.host == var.proxmox.hub.address
    error_message = "hub bootstrap host must be the Proxmox hub address"
  }

  assert {
    condition     = output.test_k3s_bootstrap_nodes.hub.host_generation == proxmox_virtual_environment_vm.hub.id
    error_message = "hub host_generation must be the hub VM id (recreate re-bootstraps the hub)"
  }

  assert {
    condition     = length(output.test_k3s_bootstrap_nodes.hub.extra_packages) == 1 && output.test_k3s_bootstrap_nodes.hub.extra_packages[0] == "qemu-guest-agent"
    error_message = "the Proxmox hub must install qemu-guest-agent (no custom cloud-init on Proxmox)"
  }

  assert {
    condition     = alltrue([for k in ["pt", "de"] : output.test_k3s_bootstrap_nodes[k].host == module.gcp_edges[k].public_ipv4])
    error_message = "edge bootstrap hosts must be the edge public IPv4s"
  }

  assert {
    condition     = alltrue([for k in ["pt", "de"] : output.test_k3s_bootstrap_nodes[k].host_generation == module.gcp_edges[k].instance_id])
    error_message = "edge host_generation must be its numeric GCP instance id"
  }

  assert {
    condition     = alltrue([for k in ["pt", "de"] : length(output.test_k3s_bootstrap_nodes[k].extra_packages) == 0])
    error_message = "GCP edges must not install qemu-guest-agent (guest agent ships with the image)"
  }
}

run "no_key_content" {
  command = plan

  assert {
    condition     = output.connection_data_hub.ssh_private_key == null
    error_message = "connection_data_hub must not carry key content"
  }

  assert {
    condition     = output.connection_data_hub.ssh_private_key_file == var.ssh_private_key_file
    error_message = "connection_data_hub must reference the stand private key by path"
  }

  assert {
    condition     = output.connection_data_hub.user == "garuda"
    error_message = "connection_data_hub user must be the k3s-bootstrap admin user"
  }

  assert {
    condition     = alltrue([for k, cd in output.connection_data_edges : cd.ssh_private_key == null && cd.ssh_private_key_file == var.ssh_private_key_file && cd.user == "garuda"])
    error_message = "every edge connection bundle must be key-path-only with user garuda"
  }

  assert {
    condition     = output.connection_data_client.ssh_private_key == null
    error_message = "connection_data_client must not carry key content"
  }

  assert {
    condition     = output.connection_data_client.ssh_private_key_file == var.ssh_private_key_file && output.connection_data_client.user == "ubuntu"
    error_message = "connection_data_client must be key-path-only with the un-bootstrapped ubuntu user"
  }
}

run "dns_scope" {
  command = plan

  assert {
    condition     = cloudflare_record.hub.name == "${var.hub_fqdn_prefix}.${var.base_domain}"
    error_message = "hub record must be inside the stand base_domain"
  }

  assert {
    condition     = cloudflare_record.panel.name == "panel.${var.base_domain}"
    error_message = "panel record must be inside the stand base_domain"
  }

  assert {
    condition     = cloudflare_record.sub.name == "sub.${var.base_domain}"
    error_message = "sub record must be inside the stand base_domain"
  }

  assert {
    condition     = alltrue([for k, r in cloudflare_record.edges : r.name == "${var.edges[k].fqdn_prefix}.${var.base_domain}"])
    error_message = "every edge record must be inside the stand base_domain"
  }
}

run "routeros_disabled_no_resources" {
  command = plan

  assert {
    condition     = length(routeros_interface_list.lan) == 0
    error_message = "routeros_interface_list must not exist when routeros_enabled is false"
  }

  assert {
    condition     = length(routeros_ip_dns.this) == 0
    error_message = "routeros_ip_dns must not exist when routeros_enabled is false"
  }

  assert {
    condition     = output.routeros == null
    error_message = "routeros output must be null when routeros_enabled is false"
  }
}

run "routeros_enabled_bootstrap_resources" {
  command = plan

  variables {
    routeros_enabled = true
    routeros = {
      hostname         = "routeros-example"
      management_host  = "203.0.113.1"
      user             = "admin"
      uplink_interface = "ether1"
    }
    routeros_password = "fixture"
  }

  assert {
    condition     = routeros_interface_list.lan[0].name == "LAN"
    error_message = "routeros_interface_list.lan name must be LAN when enabled"
  }

  assert {
    condition     = length(routeros_ip_dns.this[0].servers) == 2
    error_message = "routeros_ip_dns must have two DNS servers when enabled"
  }

  assert {
    condition     = output.routeros == var.routeros
    error_message = "routeros output must pass through var.routeros when enabled"
  }
}
