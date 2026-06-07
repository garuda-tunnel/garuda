# When adding a new edge slug, also add it to this aggregate output —
# the literal `[module.garuda_k8s_pt, module.garuda_k8s_de]` lists
# below do not auto-expand from var.edges. Mirror the per-slug pattern
# in main.tf (see "Kubernetes namespace and CNI bootstrap: edges").
# Hub-side k3s modules use `values(module.wireguard_kube_hub)` to
# auto-aggregate the for_each map.
output "workloads" {
  description = "Aggregated workload modules output for debugging."
  sensitive   = true
  value = concat(
    [module.garuda_k8s_pt, module.garuda_k8s_de],
    [module.wireguard_kube_pt, module.wireguard_kube_de],
    [module.garuda_k8s_hub, module.wireguard_kube_hub_ros, module.cert_manager, module.k8s_gateway_bootstrap, module.border_router],
    values(module.wireguard_kube_hub),
    [
      module.firezone_kube,
      module.ipt_server_kube,
    ],
  )
}

output "ansible_smoke_inventory" {
  description = "Managed hosts for Z2G smoke (hub + edges as linux_hosts + RouterOS)."
  sensitive   = true
  value = merge(
    {
      hub = {
        inventory_name               = local.host_names.hub
        ansible_host                 = var.connection_data_hub.host
        ansible_user                 = var.connection_data_hub.user
        ansible_password             = null
        ansible_connection           = var.connection_data_hub.connection
        ansible_network_os           = var.connection_data_hub.network_os
        ansible_ssh_private_key_file = var.connection_data_hub.ssh_private_key != null ? local_sensitive_file.ssh_key_hub.filename : null
        groups                       = ["linux_hosts", "k3s_hosts", "smoke_all"]
      }
    },
    {
      for k, cd in var.connection_data_edges : k => {
        inventory_name               = local.host_names[k]
        ansible_host                 = cd.host
        ansible_user                 = cd.user
        ansible_password             = null
        ansible_connection           = cd.connection
        ansible_network_os           = cd.network_os
        ansible_ssh_private_key_file = cd.ssh_private_key != null ? local_sensitive_file.ssh_key_edges[k].filename : null
        groups                       = ["linux_hosts", "k3s_hosts", "smoke_all"]
      }
    },
    {
      routeros = {
        inventory_name          = var.routeros.hostname
        ansible_host            = var.routeros.management_host
        ansible_user            = var.routeros.user
        ansible_password        = var.routeros_password
        ansible_connection      = "ansible.netcommon.network_cli"
        ansible_network_os      = "community.routeros.routeros"
        ansible_ssh_private_key = null
        groups                  = ["routeros", "smoke_all"]
      }
    },
  )
}

output "ansible_client_inventory" {
  description = "Live-smoke VPN clients (pre-existing, not managed by this stack)."
  value = {
    firezone_wg_client = {
      inventory_name     = var.smoke_client_firezone.inventory_name
      ansible_host       = var.smoke_client_firezone.management_host
      ansible_user       = var.smoke_client_firezone.user
      ansible_connection = "ssh"
      groups             = ["firezone_clients", "smoke_all"]
    }
  }
}

# Test-only outputs for structural asserts in tftest files.
output "ipt_routes_count" {
  description = "Number of ipt_routes groups."
  value       = length(local.ipt_routes)
}

output "ipt_routes_primary_gws" {
  description = "Ordered list of gw values in the default (first) ipt_routes group."
  value       = [for m in local.ipt_routes[0].route : m.gw if can(m.gw) && m.gw != null]
}

output "ipt_server_label_router_id" {
  description = "Router id passed into module.ipt_server_kube.ospf.router_id."
  value       = local.ipt_server_kube_ospf.router_id
}
