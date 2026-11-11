output "storage_class_name" {
  description = "Name of the shared Retain StorageClass for CNPG cluster PVCs (local-path-retain). Derives from the operator release so callers order after it."
  value       = kubernetes_storage_class_v1.retain.metadata[0].name

  # Belt and braces with the StorageClass edge: consumers of this output get
  # an implicit dependency on the operator release (CRDs before Clusters).
  depends_on = [helm_release.cnpg]
}
