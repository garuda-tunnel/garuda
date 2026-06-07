variable "namespace" {
  description = "Namespace for the platform Gateway (e.g., gateway-system)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid k8s namespace name."
  }
}

variable "gateway_class_name" {
  description = "Name of the GatewayClass to reference (e.g., traefik)."
  type        = string
}

variable "cluster_issuer_name" {
  description = "Name of the cert-manager ClusterIssuer to annotate the Gateway with."
  type        = string
}

variable "hostnames" {
  description = <<-EOT
    List of hostnames served by the Gateway. One HTTPS listener is rendered
    per entry, each with its own cert-manager-managed Certificate Secret.

    name: stable listener name (kebab-case, lowercase).
    hostname: FQDN matched by the listener.
    cert_secret_name: Secret name in the gateway namespace where cert-manager
      stores the issued leaf certificate.
  EOT
  type = list(object({
    name             = string
    hostname         = string
    cert_secret_name = string
  }))
  validation {
    condition     = length(var.hostnames) > 0
    error_message = "hostnames must contain at least one entry."
  }
}

variable "labels" {
  description = "Additional labels to apply to the Gateway."
  type        = map(string)
  default     = {}
}

variable "enable_traefik_gateway_provider" {
  description = <<-EOT
    When true (default), the chart renders a HelmChartConfig in kube-system
    that enables Traefik's kubernetesGateway provider and reconfigures the
    websecure entrypoint to listen on :443, without which Gateway API
    resources sit unreconciled in k3s clusters using the bundled Traefik.
    Set false if the stand already enables the provider via another
    mechanism (custom Traefik install, kustomize, etc.) to avoid
    HelmChartConfig owner conflicts.
  EOT
  type    = bool
  default = true
}
