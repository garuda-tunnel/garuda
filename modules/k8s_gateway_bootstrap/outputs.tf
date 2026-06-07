output "gateway_name" {
  description = "Name of the rendered platform Gateway resource."
  value       = local.gateway_name
}

output "gateway_namespace" {
  description = "Namespace where the platform Gateway lives."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}
