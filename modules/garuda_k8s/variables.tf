variable "namespace" {
  description = "Kubernetes namespace to create and configure."
  type        = string
  default     = "garuda"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid DNS-1123 label."
  }
}

variable "backbone_subnet" {
  description = "CIDR for the host-side `backbone` bridge IPAM, for example 10.42.0.0/24."
  type        = string

  validation {
    condition     = can(cidrhost(var.backbone_subnet, 0))
    error_message = "backbone_subnet must be a valid CIDR."
  }
}

variable "border_subnet" {
  description = "CIDR for the host-side `border` bridge IPAM, for example 10.43.0.0/24."
  type        = string

  validation {
    condition     = can(cidrhost(var.border_subnet, 0))
    error_message = "border_subnet must be a valid CIDR."
  }
}

variable "install_cni" {
  description = <<EOT
When true, the chart installs Multus using k3s-native CNI paths. Set to
false if it is pre-installed by the cluster operator.
EOT
  type        = bool
  default     = true
}

variable "pod_reaper_max_unready" {
  description = <<EOT
Override of the garuda chart's podReaper.maxUnready, for example "600s". A pod
counts as unready while its images are still being pulled, so a slow first pull
can make the reaper replace pods that were making progress. Null keeps the chart
default (120s).
EOT
  type        = string
  default     = null

  validation {
    condition     = var.pod_reaper_max_unready == null || can(regex("^[1-9][0-9]*[smh]$", var.pod_reaper_max_unready))
    error_message = "pod_reaper_max_unready must be null or match ^[1-9][0-9]*[smh]$, for example 600s."
  }
}
