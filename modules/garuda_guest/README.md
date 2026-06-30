# garuda_guest

PURE DATA — no `helm_release`, no Kubernetes resources; outputs only.

A pure-data Terraform module that composes Garuda fabric annotations, labels,
and ConfigMap intent for a vanilla guest workload. The caller passes the outputs
directly to a workload module's `podAnnotations`, `podLabels`, and `configmaps`
variables. The Garuda MAP (MutatingPolicy) then injects the frr-sidecar and
secondary-network attachment at pod admission based on these annotations.

## Design

- `output.annotations` — pod-template annotations including:
  - `net.garuda-tunnel/*` intent fields (networks CSV, router-id, interfaces, etc.)
  - `net.garuda-tunnel/profile-rev` — sha256 rollout-trigger hash (changes on ANY
    intent change or garuda chart version bump; forces a rolling update)
  - `k8s.v1.cni.cncf.io/networks` — Multus NAD attachment string (workload NADs
    prepended before fabric NADs in `name@iface` form)
- `output.labels` — pod-template label `net.garuda-tunnel/profile` (MAP dispatch key)
- `output.configmaps` — passthrough of `var.configmaps` (Tier 2/3 FRR snippet CMs)

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `profile` | `string` | yes | Fabric role: `ospf-router`, `transit-provider`, or `border`. |
| `garuda_chart_version` | `string` | yes | Deployed garuda chart version (part of profile-rev hash). |
| `networks` | `list(string)` | yes | Fabric NAD names (`backbone`, `border`). At least one required; no duplicates. |
| `ospf_router_id` | `string` | no | OSPF router-id (dotted-decimal IP). Empty = omit annotation. |
| `workload_nads` | `list(string)` | no | Workload-owned NAD names prepended before fabric NADs. No duplicates. |
| `interfaces` | `string` | no | CSV of OSPF interface names. |
| `redistribute` | `string` | no | CSV of OSPF redistribute proto names. |
| `default_originate` | `string` | no | Override profile default-originate: `""`, `"true"`, or `"false"`. |
| `transit_interfaces` | `string` | no | CSV of PBR consumer interfaces. XOR: forbidden when `profile = "transit-provider"`. |
| `nic_attach` | `string` | no | Override profile nic-attach (CSV of NAD names). |
| `mtu` | `number` | no | MTU hint (1280–1420). `null` = use profile default. |
| `sidecar_image` | `string` | no | Per-guest frr-sidecar image override. |
| `frr_mode` | `string` | no | `""` (default) or `"raw"`. Requires `frr_raw_configmap` when `raw`. |
| `frr_extra_configmap` | `string` | no | Tier 2: ConfigMap name the sidecar appends to rendered frr.conf. |
| `frr_raw_configmap` | `string` | no | Tier 3: ConfigMap name holding the full frr.conf. |
| `configmaps` | `map(map(string))` | no | Extra CMs: `{ cm-name = { filename = content } }`. Tier 3 raw MUST use filename `frr.conf`. |
| `extra_annotations` | `map(string)` | no | Escape hatch: extra pod annotations. `net.garuda-tunnel/*` and `k8s.v1.cni.cncf.io/networks` keys forbidden. |

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `annotations` | `map(string)` | Pod-template annotations (net.garuda-tunnel/* + k8s.v1.cni.cncf.io/networks + profile-rev). |
| `labels` | `map(string)` | Pod-template label `net.garuda-tunnel/profile`. |
| `configmaps` | `map(map(string))` | Passthrough of `var.configmaps`. |

## Example (stand wiring — spec §10.2)

```hcl
module "wg_hub_ros_guest" {
  source = "../../modules/garuda_guest"

  profile              = "ospf-router"
  ospf_router_id       = "10.130.30.22"
  networks             = ["backbone", "border"]
  interfaces           = "backbone,border"
  redistribute         = "connected"
  garuda_chart_version = module.garuda.chart_version
}

module "wireguard" {
  source = "git::https://github.com/garuda-tunnel/wireguard-internal.git//kube?ref=main"

  # ... workload-specific vars ...

  annotations = module.wg_hub_ros_guest.annotations
  labels      = module.wg_hub_ros_guest.labels
  configmaps  = module.wg_hub_ros_guest.configmaps

  depends_on = [time_sleep.map_propagation]
}
```

## Profile-rev hash

The `net.garuda-tunnel/profile-rev` annotation is a deterministic sha256 of all
intent fields plus `garuda_chart_version`. Any change to these fields produces a
different hash, which causes the workload Deployment to roll its pods (Kubernetes
rolls pods when pod-template annotations change). The hash field order is fixed —
do not reorder the `intent_hash` keys in `main.tf`.

## Validation rules

- `profile`: must be `ospf-router`, `transit-provider`, or `border`
- `networks`: non-empty; only `backbone` or `border`; no duplicates
- `workload_nads`: no duplicates
- `ospf_router_id`: dotted-decimal IP or empty string
- `default_originate`: `""`, `"true"`, or `"false"`
- `transit_interfaces`: forbidden when `profile = "transit-provider"` (XOR invariant)
- `mtu`: null or 1280–1420
- `frr_mode`: `""` or `"raw"`; `raw` requires `frr_raw_configmap`; `raw` forbids `interfaces`/`redistribute`
- `extra_annotations`: `net.garuda-tunnel/*` and `k8s.v1.cni.cncf.io/networks` keys forbidden
