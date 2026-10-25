# Aggregated workload modules output (debug). Edge modules are for_each maps,
# so they auto-expand via values()/[for ...] — no manual per-edge edit needed.
output "workloads" {
  description = "Aggregated workload modules output for debugging."
  sensitive   = true
  value = concat(
    values(module.garuda_k8s),
    [for m in module.wireguard_kube_edge : m],
    [module.garuda_k8s_hub],
    module.wireguard_kube_hub_ros,
    [module.cert_manager, module.k8s_gateway_bootstrap, module.border_router],
    values(module.wireguard_kube_hub),
    [
      module.firezone_kube,
      module.ipt_server_kube,
    ],
  )
}

# Test-only outputs for structural asserts in tftest files.
output "mtu_policy" {
  description = "Site MTU policy (not sensitive); the local-stand e2e output publishes it for the pytest suite."
  value       = { site_mtu = local.mtu_policy.site_mtu }
}

output "ipt_route_groups_egress" {
  description = "Effective ipt_server route groups expressed as roles (edge keys / \"border\") with their destination rules."
  value       = local.ipt_route_groups_effective
}

output "ipt_routes_count" {
  description = "Number of ipt_routes groups."
  value       = length(local.ipt_routes)
}

output "ipt_routes_primary_gws" {
  description = "Ordered list of gw values in the default (first) ipt_routes group."
  value       = [for m in local.ipt_routes[0].route : m.gw if can(m.gw) && m.gw != null]
}

output "ipt_server_label_router_id" {
  description = "Router id for the ipt_server workload (now from garuda_guest intent)."
  value       = var.ospf_router_ids.ipt_server
}

output "remnawave_node_control_service_dns" {
  description = "Cluster DNS name registered for Remnawave node control."
  value       = one(module.remnawave_panel[*].node_control_service_dns)
}

output "remnawave_node_hysteria_udp_port" {
  description = "Reserved Hysteria UDP hostPort for Remnawave node ingress."
  value       = one(module.remnawave_panel[*].node_hysteria_udp_port)
}

output "remnawave_node_ospf_router_id" {
  description = "Stable advertised /32 for Remnawave node pinning."
  value       = one(module.remnawave_panel[*].node_ospf_router_id)
}
