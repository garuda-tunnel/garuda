variable "chart_version" {
  description = <<-EOT
    CloudNativePG operator Helm chart version (chart `cloudnative-pg` from
    oci://ghcr.io/cloudnative-pg/charts). No default — callers pin it
    explicitly, annotated with `# renovate: datasource=docker depName=ghcr.io/cloudnative-pg/charts/cloudnative-pg`.
  EOT
  type        = string

  validation {
    condition     = length(var.chart_version) > 0
    error_message = "chart_version must not be empty (an empty helm version installs the latest chart)."
  }
}
