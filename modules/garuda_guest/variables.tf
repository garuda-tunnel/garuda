variable "profile" {
  description = "Fabric role. Sets the net.garuda-tunnel/profile label (MAPBinding dispatch key)."
  type        = string
  validation {
    condition     = contains(["ospf-router", "transit-provider", "border"], var.profile)
    error_message = "profile must be one of: ospf-router, transit-provider, border."
  }
}

variable "ospf_router_id" {
  description = "Explicit OSPF router-id (dotted-decimal IP). Empty when the workload does not run OSPF."
  type        = string
  default     = ""
  validation {
    condition     = var.ospf_router_id == "" || can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.ospf_router_id))
    error_message = "ospf_router_id must be a valid dotted-decimal IP or an empty string."
  }
}

variable "networks" {
  description = "Fabric NAD names to attach. Composed into k8s.v1.cni.cncf.io/networks as name@iface."
  type        = list(string)
  validation {
    condition     = length(var.networks) > 0
    error_message = "networks must contain at least one fabric NAD (backbone or border)."
  }
  validation {
    condition     = alltrue([for n in var.networks : contains(["backbone", "border"], n)])
    error_message = "networks must contain only known fabric NAD names: backbone, border."
  }
  validation {
    condition     = length(distinct(var.networks)) == length(var.networks)
    error_message = "networks must not contain duplicate NAD names."
  }
}

variable "workload_nads" {
  description = "Workload-owned NAD names (e.g. wg-firezone) joined before fabric NADs in the networks annotation."
  type        = list(string)
  default     = []
  validation {
    condition     = length(distinct(var.workload_nads)) == length(var.workload_nads)
    error_message = "workload_nads must not contain duplicate NAD names."
  }
}

variable "interfaces" {
  description = "CSV of interface names OSPF runs on (net.garuda-tunnel/interfaces). Empty when not an OSPF role."
  type        = string
  default     = ""
}

variable "redistribute" {
  description = "CSV of OSPF redistribute proto names (net.garuda-tunnel/redistribute)."
  type        = string
  default     = ""
}

variable "passive_interfaces" {
  description = "CSV of interface names that run OSPF passively (net.garuda-tunnel/passive-interfaces). The sidecar renders these as `ip ospf area 0.0.0.0` + `ip ospf passive` (no hello/dead timers, no mtu-ignore) and excludes them from the active interfaces timer stanzas. Empty when no passive interfaces."
  type        = string
  default     = ""
}

variable "default_originate" {
  description = "Override profile default-originate. One of \"\", \"true\", \"false\"."
  type        = string
  default     = ""
  validation {
    condition     = contains(["", "true", "false"], var.default_originate)
    error_message = "default_originate must be one of: \"\" (unset), \"true\", \"false\"."
  }
}

variable "transit_interfaces" {
  description = "CSV of PBR consumer interfaces (net.garuda-tunnel/transit-interfaces). XOR with profile=transit-provider."
  type        = string
  default     = ""
  validation {
    condition     = !(var.profile == "transit-provider" && var.transit_interfaces != "")
    error_message = "profile 'transit-provider' must not set transit_interfaces (XOR invariant)."
  }
}

variable "nic_attach" {
  description = "Override profile default nic-attach (net.garuda-tunnel/nic-attach), CSV of NAD names."
  type        = string
  default     = ""
}

variable "mtu" {
  description = "MTU hint (net.garuda-tunnel/mtu). null = use profile default. Clamp stays workload-native."
  type        = number
  default     = null
  validation {
    condition     = var.mtu == null || (var.mtu >= 1280 && var.mtu <= 1420)
    error_message = "mtu must be null or in the range 1280..1420."
  }
}

variable "sidecar_image" {
  description = "Per-guest frr-sidecar image override (net.garuda-tunnel/sidecar-image)."
  type        = string
  default     = ""
}

variable "frr_mode" {
  description = "Tier 3 escape hatch flag (net.garuda-tunnel/frr-mode). One of \"\" or \"raw\"."
  type        = string
  default     = ""
  validation {
    condition     = contains(["", "raw"], var.frr_mode)
    error_message = "frr_mode must be \"\" or \"raw\"."
  }
  validation {
    condition     = !(var.frr_mode == "raw" && var.frr_raw_configmap == "")
    error_message = "frr_mode=raw requires frr_raw_configmap to name the raw ConfigMap."
  }
  validation {
    condition     = !(var.frr_mode == "raw" && (var.interfaces != "" || var.redistribute != ""))
    error_message = "frr_mode=raw forbids interfaces and redistribute (raw ConfigMap is authoritative)."
  }
  validation {
    condition     = !(var.frr_mode == "raw" && var.frr_extra_configmap != "")
    error_message = "frr_mode=raw forbids frr_extra_configmap (raw ConfigMap is authoritative; nothing to append)."
  }
}

variable "frr_extra_configmap" {
  description = "Tier 2: ConfigMap name the sidecar appends to rendered frr.conf (net.garuda-tunnel/frr-extra-configmap)."
  type        = string
  default     = ""
}

variable "frr_raw_configmap" {
  description = "Tier 3: ConfigMap name holding the full frr.conf (net.garuda-tunnel/frr-raw-configmap)."
  type        = string
  default     = ""
}

variable "garuda_chart_version" {
  description = "Deployed garuda chart version. Part of the profile-rev rollout-trigger hash."
  type        = string
}

variable "configmaps" {
  description = "Passthrough to the guest's configmaps output. key=CM name, value={ filename => content }. Tier 3 raw MUST use filename \"frr.conf\" (render_frr.py:224); Tier 2 uses any *.conf filename."
  type        = map(map(string))
  default     = {}
}

variable "extra_annotations" {
  description = "Escape hatch: extra pod annotations. Reserved net.garuda-tunnel/* and k8s.v1.cni.cncf.io/networks keys are forbidden (would desync the profile-rev hash)."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for k in keys(var.extra_annotations) : !startswith(k, "net.garuda-tunnel/") && k != "k8s.v1.cni.cncf.io/networks"])
    error_message = "extra_annotations must not contain reserved net.garuda-tunnel/* or k8s.v1.cni.cncf.io/networks keys."
  }
}
