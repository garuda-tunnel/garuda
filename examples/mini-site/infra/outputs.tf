# Hub SSH connection bundle (single object). Key path only — key content
# never leaves the caller (C7); user is the k3s-bootstrap admin.
output "connection_data_hub" {
  description = "SSH connection bundle for the hub host (user garuda, stand key by path)."
  sensitive   = true
  value = {
    host                 = var.proxmox.hub.address
    user                 = "garuda"
    connection           = "ssh"
    network_os           = "linux"
    password             = null
    ssh_private_key_file = var.ssh_private_key_file
    ssh_private_key      = null
    instance_token       = proxmox_virtual_environment_vm.hub.id
  }
}

# Edge SSH connection bundles (map keyed by edge slug: pt, de, …), brought to
# the same key-path-only shape (the module would otherwise expose its
# generated key; with ssh_public_key set it is null already).
output "connection_data_edges" {
  description = "Per-edge SSH connection bundles (keyed by edge slug, user garuda, stand key by path)."
  sensitive   = true
  value = {
    for k, m in module.gcp_edges : k => merge(m.connection_data, {
      user                 = "garuda"
      ssh_private_key_file = var.ssh_private_key_file
      ssh_private_key      = null
    })
  }
}

# Test-client VM connection bundle. The client is not bootstrapped, so the
# cloud-init user is the only login.
output "connection_data_client" {
  description = "SSH connection bundle for the Proxmox test-client VM (user ubuntu, stand key by path)."
  sensitive   = true
  value = {
    host                 = var.proxmox.client.address
    user                 = "ubuntu"
    connection           = "ssh"
    network_os           = "linux"
    password             = null
    ssh_private_key_file = var.ssh_private_key_file
    ssh_private_key      = null
    instance_token       = proxmox_virtual_environment_vm.client.id
  }
}

# Cloudflare record for the hub host (used by garuda/ as WG endpoint host).
output "cloudflare_hub" {
  description = "Cloudflare record for hub (FQDN used as WG endpoint host)."
  value = {
    zone_id     = data.cloudflare_zone.main.id
    record_name = cloudflare_record.hub.hostname
  }
}

# Cloudflare records for edges (keyed by edge slug).
output "cloudflare_edges" {
  description = "Cloudflare records for edge hosts (keyed by edge slug)."
  value = {
    for k, r in cloudflare_record.edges : k => {
      zone_id     = data.cloudflare_zone.main.id
      record_name = r.hostname
    }
  }
}

# RouterOS handles pulled from variables (not Terraform-managed ingress).
# Kept here so garuda/ consumes one "infra facts" surface via dependency;
# null when routeros_enabled is false.
output "routeros" {
  description = "RouterOS connection handles."
  value       = var.routeros_enabled ? var.routeros : null
}

# --- Testing-only outputs ------------------------------------------------
# Expose the per-node k3s-bootstrap wiring so terraform tests can assert the
# host/host_generation/extra_packages contract without reaching into the
# (override_module'd) module.
output "test_k3s_bootstrap_nodes" {
  description = "Internal: per-node k3s-bootstrap wiring (host, host_generation, extra_packages). Testing use only."
  value       = local.k3s_nodes
}
