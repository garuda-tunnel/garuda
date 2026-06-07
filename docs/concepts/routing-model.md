# Routing Model

## OSPF sidecar model

Garuda does not configure routing on the host directly. Instead, FRR speakers run
as sidecar containers that share the network namespace of their target workload pod.
Each sidecar has:

- An `ospfd` process listening on the `backbone` Multus interface and any additional
  interfaces declared in the module's `ospf.interfaces` input.
- A per-workload router ID taken from `ospf.router_id`.

OSPF intent is expressed as a structured `ospf` object in each workload module's
`variables.tf`. The FRR sidecar renders `frr.conf` from this object at deploy time.
No per-workload `frr.conf` template is maintained by hand.

The FRR sidecar is delivered by the `frr-sidecar` Helm chart published to
`oci://ghcr.io/garuda-tunnel/charts` (source: `garuda-tunnel/frr-sidecar`), consumed
via a `dependencies:` entry in each workload chart. No sidecar container spec is
inlined or vendored.

## Transit routing

Transit routing answers the question: "how does a Firezone user's packet reach
`ipt_server` without hard-coding the `ipt_server` backbone IP anywhere?"

1. The `ipt_server` FRR sidecar originates a default route as an OSPF External LSA
   with `tag=100` and `forwarding-address=0.0.0.0`.
2. On every transit consumer (a workload module with a non-empty `transit.interfaces`
   input, such as `wireguard/kube` for the RouterOS tunnel or `firezone/kube`),
   the FRR sidecar runs a `transit-watcher` loop.
3. The watcher reads the OSPF external LSA database, finds the LSA with the
   configured tag, resolves the advertising router's backbone address, and writes
   `ip route replace default via <addr> dev backbone table 201`.
4. `pbrd` programs a rule `iif <transit-iface> lookup 201` from the workload's
   PBR map.
5. Traffic entering through the transit interface uses table 201; everything else
   follows the main table.

When `ipt_server` goes away the External LSA disappears. The watcher stops
refreshing table 201; stale entries time out and the rule falls through to the
main table. This is the documented degraded mode.

## Geo and domain policy-based routing (PBR)

Policy rules in `ipt_server` describe where categories of traffic should exit the
mesh. Each rule entry has:

- `rules` — a `list(string)` of matchers. Type is inferred by `ipt_server`:
  - CIDR pattern → `net` matcher.
  - ISO 3166-1 alpha-2 code (e.g. `RU`, `DE`) → `country` (geo) matcher.
  - Regular expression (e.g. `.*\.ru`) → `domain` matcher.
- `route` — where to send matching traffic: `{ gw = "<ip>" }` for a concrete
  next-hop or `{ dev = "<interface>" }` for a device.

At runtime `ipt_server`:

1. Intercepts DNS responses and resolves matching IPs for domain/geo rules.
2. Marks matching flows with `fwmark`.
3. Programs kernel policy rules so marked packets look up a dedicated routing table
   and exit through the correct next-hop or device.

Full schema: [`docs/reference/routing-policy.md`](../reference/routing-policy.md).

## Per-source egress pinning

`ipt_server` supports a pinning feature that assigns individual source clients to
a specific egress. When a client performs a pinned lookup, `ipt_server` records the
client's source IP and enforces a consistent egress for subsequent traffic, for up
to `pinning_ttl` seconds.

Configuration:

```hcl
pinning_egress = {
  usa = { gw = "192.0.2.2" }
}
pinning_ttl = 86400
```

Setting `pinning_egress = {}` disables the feature entirely.

## Failover behavior

**Egress node fails.** The WireGuard tunnel keepalive stops, the OSPF neighbor
ages out, and the External LSA from that egress leaves the LSDB. If another egress
advertises the same route, zebra switches to it and consumers continue routing
through the mesh. If no alternative exists, table 201 becomes unreachable and
traffic falls through to the main table.

**`ipt_server` fails.** The FRR sidecar stops, OSPF drops the adjacency, and the
External LSA with `tag=100` disappears. Transit watchers stop refreshing table 201.
Consumer traffic falls through to the main table. Effect: no more geo-based routing
until `ipt_server` recovers.

**Hub fails.** RouterOS loses its tunnel peer but its LAN continues working through
the local uplink. Firezone users lose service; the current topology has a single hub.
Multi-hub is a deliberate future change.

## Further reading

- [Architecture](architecture.md) — planes, node roles, module boundaries.
- [Routing policy reference](../reference/routing-policy.md) — exact `routes` and
  `pinning_egress` schemas.
