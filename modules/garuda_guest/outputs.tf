output "annotations" {
  description = "Pod-template annotations: net.garuda-tunnel/* intent + k8s.v1.cni.cncf.io/networks + profile-rev."
  value       = local.composed_annotations
}

output "labels" {
  description = "Pod-template labels: the net.garuda-tunnel/profile dispatch label."
  value       = { "net.garuda-tunnel/profile" = var.profile }
}

output "configmaps" {
  description = "Extra ConfigMaps the vanilla guest must create before pod admission (Tier 2/3)."
  value       = var.configmaps
}
