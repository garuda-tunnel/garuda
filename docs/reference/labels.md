# OSPF Module Input Schema

Garuda uses a structured `ospf` object to carry FRR/OSPF intent into workload
modules. This replaces the Docker label taxonomy used in the pre-k3s era.

> **Historical note.** The previous approach used Docker container labels
> (e.g. `garuda.frr.ospf.enabled`, `garuda.transit.provider`, `garuda.managed-by`)
> read by the `ospf_injector` runtime operator to discover workloads and reconcile
> FRR sidecars. That operator was removed in the k3s migration. OSPF intent is now
> expressed as a structured Terraform variable, not as runtime-discovered Docker
> labels.

## ospf object

The `ospf` variable is accepted by `wireguard/kube`, `firezone/kube`,
`ipt_server/kube`, and `border_router`. When `null` or absent, no FRR sidecar is
rendered.

| Field                | Type            | Required | Description                                              |
|----------------------|-----------------|----------|----------------------------------------------------------|
| `router_id`          | string (IPv4)   | yes      | Unique OSPF router-id for this workload.                 |
| `area`               | string          | no       | OSPF area. Default `"0.0.0.0"`.                          |
| `interfaces`         | list(string)    | yes      | Interfaces participating in OSPF (e.g. `["backbone", "wg-pt"]`). |
| `passive_interfaces` | list(string)    | no       | Interfaces marked `ip ospf passive`.                     |
| `default_originate`  | bool            | no       | Originate a default route as OSPF External LSA. Default `false`. |
| `redistribute`       | list(string)    | no       | FRR redistribution sources, e.g. `["connected", "kernel"]`. |
| `transit_provider`   | bool            | no       | Mark this workload as transit route provider (`ipt_server`). |
| `extra_frr_conf`     | string          | no       | Free-form FRR config appended verbatim to `frr.conf`.    |

## transit object

The `transit` variable is accepted by workload modules that route user traffic
through `ipt_server` (e.g. `firezone/kube`, `wireguard/kube` for the RouterOS
tunnel).

| Field        | Type         | Description                                                                |
|--------------|--------------|----------------------------------------------------------------------------|
| `interfaces` | list(string) | Interfaces whose inbound traffic uses the transit routing table (table 201). |

When `transit.interfaces` is set, the FRR sidecar runs a `transit-watcher` loop
that installs `ip rule iif <iface> lookup 201` rules and resolves the OSPF-
advertised default route into table 201.

## Minimal ospf sets by workload type

### WireGuard k3s egress peer (edge side — transit provider)

```hcl
ospf = {
  router_id         = "192.0.2.11"
  interfaces        = ["wg-pt"]
  passive_interfaces = []
  default_originate = true
  redistribute      = []
  transit_provider  = true
}
```

### WireGuard k3s hub peer (hub side of an edge tunnel)

```hcl
ospf = {
  router_id         = "192.0.2.12"
  interfaces        = ["backbone", "wg-pt"]
  passive_interfaces = []
  default_originate = false
  redistribute      = []
}
```

### Firezone (transit consumer)

```hcl
ospf = {
  router_id          = "192.0.2.20"
  interfaces         = ["backbone", "wg-firezone"]
  passive_interfaces = ["wg-firezone"]
  default_originate  = false
  redistribute       = ["connected", "kernel"]
}
transit = {
  interfaces = ["wg-firezone"]
}
```

### ipt_server (transit provider)

```hcl
ospf = {
  router_id  = "192.0.2.30"
  interfaces = ["backbone"]
}
```

The `ipt_server/kube` module sets the remaining transit-provider invariants
internally (`transit_provider=true`, `default_originate=true`,
`redistribute=["kernel"]`). Callers supply `router_id` and `interfaces`.

## FRR sidecar library chart

All OSPF intent is rendered into `frr.conf` by the `frr-sidecar` Helm chart
published to `oci://ghcr.io/garuda-tunnel/charts` (source: `garuda-tunnel/frr-sidecar`).
Consumer charts declare it as a `dependencies:` entry and call its named templates
(`frr-sidecar.container`, `frr-sidecar.volume`, `frr-sidecar.configmap`).

For the full FRR config rendering specification, see:

- [garuda-tunnel/frr-sidecar](https://github.com/garuda-tunnel/frr-sidecar)
- [AGENTS.md — FRR sidecar reuse rule](../../AGENTS.md)
