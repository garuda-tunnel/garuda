variable "namespace" {
  description = "Existing namespace for the Cluster and its <name>-app Secret. Created by the app module, never here."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a DNS-1123 label."
  }
}

variable "name" {
  description = <<-EOT
    Cluster and Helm release name. The operator names the application
    Secret <name>-app and the RW service <name>-rw after it.
  EOT
  type        = string
  default     = "postgres"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a DNS-1123 label."
  }

  validation {
    # CNPG derives names like <name>-rw, <name>-app, <name>-1-<ordinal>-pvc
    # from it; 50 keeps every derived name inside the chart's 63-char trunc.
    condition     = length(var.name) <= 50
    error_message = "name must be at most 50 characters so derived names stay under the 63-char limit."
  }
}

variable "database" {
  description = "Database created by bootstrap.initdb; the app consumes it via the dbname key of the <name>-app Secret."
  type        = string
}

variable "owner" {
  description = "Role that owns the database; the operator puts its credentials into the <name>-app Secret. Firezone migrations run as this owner and create their own extensions."
  type        = string
}

variable "storage_size" {
  description = "PVC size for the cluster data volume, as a Kubernetes quantity."
  type        = string
  default     = "2Gi"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(Ei|Pi|Ti|Gi|Mi|Ki|E|P|T|G|M|k|m)?$", var.storage_size))
    error_message = "storage_size must be a Kubernetes quantity like 2Gi."
  }
}

variable "storage_class" {
  description = "StorageClass for the cluster PVCs. Must be a Retain class (module.cnpg_operator.storage_class_name) — CNPG owns the Cluster's PVCs, so a Delete class destroys the data volume with the Cluster."
  type        = string
  default     = "local-path-retain"
}

variable "image" {
  description = "PostgreSQL instance image, `tag@digest`-pinned (imageName). The org Renovate regex cannot parse such tags (no `X.Y.Z`, no digest capture), so callers mark the pin with a `# shortcut:` hand-bump note instead of a `# renovate:` annotation."
  type        = string

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}

variable "chart_version" {
  description = "CloudNativePG `cluster` Helm chart version (oci://ghcr.io/cloudnative-pg/charts). No default — callers pin it explicitly, annotated with `# renovate: datasource=docker depName=ghcr.io/cloudnative-pg/charts/cluster` for repin."
  type        = string

  validation {
    condition     = length(var.chart_version) > 0
    error_message = "chart_version must not be empty (an empty helm version installs the latest chart)."
  }
}
