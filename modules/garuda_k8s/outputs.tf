output "namespace" {
  description = "Namespace created by the chart. Consumed by modules/wireguard/kube."
  value       = kubernetes_namespace_v1.garuda.metadata[0].name

  # Consumers use this output to place workloads into the namespace. Make the
  # output depend on the CNI/NAD bootstrap too, so workload pods cannot be
  # created before Multus and the NetworkAttachmentDefinitions are ready.
  depends_on = [helm_release.garuda]
}

output "backbone_nad_name" {
  description = "Name of the NetworkAttachmentDefinition for the backbone."
  value       = "backbone"
}

output "border_nad_name" {
  description = "Name of the NetworkAttachmentDefinition for the border."
  value       = "border"
}

output "map_propagation_id" {
  description = "Opaque id of the time_sleep.map_propagation resource. Stand-level workload modules add this to depends_on (Phase 5 wiring) to guarantee MAP/MAPBinding propagation before any workload pod is admitted. 10s sleep absorbs the ~3-5s observed propagation latency (spec §8.3)."
  value       = time_sleep.map_propagation.id
}
