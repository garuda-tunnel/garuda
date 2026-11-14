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
Trap: the persist-multus-conf init container leaves
00-multus-persistent.conf in the CNI conf dir (/var/lib/rancher/k3s/agent/etc/cni/net.d)
after the release is gone (install_cni=false or module destroy); it delegates to
multus-shim, which waits for the Multus daemon, so delete the file by hand when
removing garuda-cni from a node.
EOT
  type        = bool
  default     = true
}

variable "mtu_policy" {
  description = "Site MTU/MSS policy. site_mtu derives effective_mtu and fixed_mss; otherwise effective_mtu and fixed_mss must be supplied explicitly. garuda_k8s uses effective_mtu as the `border` NAD's bridge MTU; fixed_mss and mss_clamp_enabled belong to the component modules."
  nullable    = false
  default     = { site_mtu = 1330 }

  type = object({
    site_mtu          = optional(number)
    effective_mtu     = optional(number)
    fixed_mss         = optional(number)
    mss_clamp_enabled = optional(bool, true)
  })

  validation {
    condition = (
      (var.mtu_policy.site_mtu != null && var.mtu_policy.effective_mtu == null && var.mtu_policy.fixed_mss == null) ||
      (var.mtu_policy.site_mtu == null && var.mtu_policy.effective_mtu != null && var.mtu_policy.fixed_mss != null)
    )
    error_message = "Set either mtu_policy.site_mtu or both mtu_policy.effective_mtu and mtu_policy.fixed_mss."
  }

  validation {
    condition = (
      var.mtu_policy.site_mtu == null ||
      (var.mtu_policy.site_mtu >= 1280 && var.mtu_policy.site_mtu <= 1420)
    )
    error_message = "mtu_policy.site_mtu must be between 1280 and 1420."
  }

  validation {
    condition = (
      var.mtu_policy.effective_mtu == null ||
      (var.mtu_policy.effective_mtu >= 1280 && var.mtu_policy.effective_mtu <= 1420)
    )
    error_message = "mtu_policy.effective_mtu must be between 1280 and 1420."
  }

  validation {
    condition = (
      var.mtu_policy.fixed_mss == null ||
      (var.mtu_policy.fixed_mss >= 536 && var.mtu_policy.fixed_mss <= 1460)
    )
    error_message = "mtu_policy.fixed_mss must be between 536 and 1460."
  }

  validation {
    condition = (
      var.mtu_policy.fixed_mss == null ||
      var.mtu_policy.effective_mtu == null ||
      var.mtu_policy.fixed_mss <= var.mtu_policy.effective_mtu - 40
    )
    error_message = "mtu_policy.fixed_mss must be less than or equal to mtu_policy.effective_mtu - 40."
  }
}

variable "pod_reaper_max_unready" {
  description = <<EOT
Override of the garuda chart's podReaper.maxUnready, for example "600s": how
long a crash-looping unready pod is tolerated before the reaper evicts it. Pods
without a sandbox or still pulling images are never reaped (issue #179). Null
keeps the chart default (120s).
EOT
  type        = string
  default     = null

  validation {
    condition     = var.pod_reaper_max_unready == null || can(regex("^[1-9][0-9]*[smh]$", var.pod_reaper_max_unready))
    error_message = "pod_reaper_max_unready must be null or match ^[1-9][0-9]*[smh]$, for example 600s."
  }
}
