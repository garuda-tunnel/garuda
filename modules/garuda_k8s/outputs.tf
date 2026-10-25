output "namespace" {
  description = "Namespace created by the chart. Consumed by modules/wireguard/kube."
  value       = kubernetes_namespace_v1.garuda.metadata[0].name

  # Consumers use this output to place workloads into the namespace. Make the
  # output depend on the CNI/NAD bootstrap too, so workload pods cannot be
  # created before Multus and the NetworkAttachmentDefinitions are ready, and
  # on the MAP/MAPBinding propagation sleep so pods are not admitted before the
  # injection policy is enforced.
  depends_on = [helm_release.garuda, time_sleep.map_propagation]
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

output "chart_version" {
  description = "Version of the bundled garuda umbrella chart, read from its Chart.yaml. Consumed as the garuda_chart_version input to garuda_guest so the profile-rev rollout-trigger hash can never drift from the deployed chart."
  value       = yamldecode(file("${path.module}/charts/garuda/Chart.yaml")).version
}
