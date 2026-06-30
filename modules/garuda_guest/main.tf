locals {
  # --- k8s.v1.cni.cncf.io/networks composition (Form A: name@iface) ---
  fabric_nads_csv   = join(",", [for n in var.networks : "${n}@${n}"])
  workload_nads_csv = length(var.workload_nads) > 0 ? join(",", var.workload_nads) : ""
  networks_csv      = local.workload_nads_csv != "" ? "${local.workload_nads_csv},${local.fabric_nads_csv}" : local.fabric_nads_csv

  # --- profile-rev rollout-trigger hash (no file reads; pure input-based) ---
  # DO NOT REORDER OR RENAME these keys — would flip the hash across the whole
  # fleet and force spurious rolling updates. mtu is normalised to a string so
  # null/number representation changes cannot churn the hash. configmaps CONTENT
  # is hashed so Tier 2/3 edits trigger a rollout (sidecar renders at start only).
  intent_hash = sha256(jsonencode({
    profile             = var.profile
    ospf_router_id      = var.ospf_router_id
    networks            = var.networks
    workload_nads       = var.workload_nads
    interfaces          = var.interfaces
    passive_interfaces  = var.passive_interfaces
    redistribute        = var.redistribute
    default_originate   = var.default_originate
    transit_interfaces  = var.transit_interfaces
    nic_attach          = var.nic_attach
    mtu                 = var.mtu == null ? "" : tostring(var.mtu)
    sidecar_image       = var.sidecar_image
    frr_mode            = var.frr_mode
    frr_extra_configmap = var.frr_extra_configmap
    frr_raw_configmap   = var.frr_raw_configmap
    configmaps          = var.configmaps
  }))
  config_hash = sha256("${local.intent_hash}:${var.garuda_chart_version}")

  # --- intent annotations, empty values omitted (Decision #7) ---
  intent_annotations = merge(
    { "net.garuda-tunnel/networks" = local.networks_csv },
    { "net.garuda-tunnel/profile-rev" = local.config_hash },
    var.ospf_router_id == "" ? {} : { "net.garuda-tunnel/router-id" = var.ospf_router_id },
    var.interfaces == "" ? {} : { "net.garuda-tunnel/interfaces" = var.interfaces },
    var.passive_interfaces == "" ? {} : { "net.garuda-tunnel/passive-interfaces" = var.passive_interfaces },
    var.redistribute == "" ? {} : { "net.garuda-tunnel/redistribute" = var.redistribute },
    var.default_originate == "" ? {} : { "net.garuda-tunnel/default-originate" = var.default_originate },
    var.transit_interfaces == "" ? {} : { "net.garuda-tunnel/transit-interfaces" = var.transit_interfaces },
    var.nic_attach == "" ? {} : { "net.garuda-tunnel/nic-attach" = var.nic_attach },
    var.mtu == null ? {} : { "net.garuda-tunnel/mtu" = tostring(var.mtu) },
    var.sidecar_image == "" ? {} : { "net.garuda-tunnel/sidecar-image" = var.sidecar_image },
    var.frr_mode == "" ? {} : { "net.garuda-tunnel/frr-mode" = var.frr_mode },
    var.frr_extra_configmap == "" ? {} : { "net.garuda-tunnel/frr-extra-configmap" = var.frr_extra_configmap },
    var.frr_raw_configmap == "" ? {} : { "net.garuda-tunnel/frr-raw-configmap" = var.frr_raw_configmap },
  )

  # Pre-composed Multus annotation lives in the same map; vanilla guest sets it in podAnnotations.
  # extra_annotations merged FIRST so computed garuda keys always win (defence-in-depth
  # alongside the reserved-key validation on var.extra_annotations).
  composed_annotations = merge(
    var.extra_annotations,
    local.intent_annotations,
    { "k8s.v1.cni.cncf.io/networks" = local.networks_csv },
  )
}
