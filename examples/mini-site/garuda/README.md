# mini-site / garuda

This Terragrunt unit deploys Garuda workloads. It depends on `infra/` outputs.

## Responsibilities

- Deploy hub workloads: backbone network, Firezone, `ipt_server`.
- Deploy edge WireGuard tunnels (Linux peer) for each entry in `edges` map.
- Deploy hub-to-RouterOS WireGuard tunnel (single path).
- Configure routing policy via `routes` and `pinning_egress`.

## Inputs consumed from infra/

| Input                  | Source          |
|------------------------|-----------------|
| `connection_data_hub`  | `infra/` output |
| `connection_data_edges`| `infra/` output |
| `cloudflare_hub`       | `infra/` output |
| `cloudflare_edges`     | `infra/` output |
| `routeros`             | `infra/` output |

## Stand opt-out flags and overrides

Defaults reproduce the cloud plan. A local stand can turn pieces off:

| Input | Default | Effect |
|---|---|---|
| `routeros_enabled` | `true` | `false` drops the hub-ros tunnel, RouterOS NAT/route; `routeros*`, `hub_ros` and `routeros_lan_gateway` may then be null. Use only for stands without RouterOS objects in state. |
| `remnawave_enabled` | `true` | `false` drops the Remnawave panel/node, their gateway hostnames and outputs (null). |
| `firezone_oidc_enabled` | `true` | `false` configures no OIDC provider; the Google client id/secret may be null. |
| `ipt_route_groups` | `null` | List of `{ egress = [edge key or "border"], rules = [...] }` replacing the built-in routing; effective roles are exposed as output `ipt_route_groups_egress`. |
| `cert_manager_solver`, `cert_manager_rfc2136`, `cert_manager_acme_ca_bundle`, `cert_manager_extra_args` | `http01`, `null`, `null`, `[]` | RFC 2136 DNS-01 solver, ACME CA bundle and controller args (see `modules/cert_manager`). |
| `host_lans` | `{}` | RFC 1918 LANs behind a node host, keyed by `hub` or an edge key: the border-owner pod gets a static route, redistributes it into OSPF and holds `host_lan_alias`; the node gets a return route for `firezone_client_subnet` (see `examples/local-stand`). |
| `host_lan_alias` | `"169.254.1.1"` | Next hop of the node's return route, deliberately outside `border_subnet`. Avoid on Calico clusters, where this address is the pod gateway. |
| `pod_reaper_max_unready` | `null` | `podReaper.maxUnready` override on every cluster: how long a crash-looping unready pod is tolerated before eviction, for example `"600s"`. |
| `ipt_powerdns_extra_config` | `""` | Raw PowerDNS Recursor YAML drop-in for the ipt-server workload Recursor (`forward_zones_recurse`, `dnssec.negative_trustanchors`); empty adds nothing. |

The gated resources use `count`; `moved` blocks in `main.tf` keep their state
addresses (`x` to `x[0]`) so default plans show no destroy/create.

## Operator prerequisites

This unit's Terragrunt wrapper invokes `garuda-tunnel` through `uvx` in a
`before_hook` to open an SSH local-forward to each edge k3s apiserver
and fetch its kubeconfig in the same SSH session. The only operator
prerequisite is `uv` on `$PATH`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

The hook pins `garuda-tunnel` to
`git+https://github.com/garuda-tunnel/garuda-tunnel.git@main`. `uvx` caches
the install in `~/.cache/uv/` and only re-resolves when the `main` HEAD
moves. To freeze, replace `@main` with `@<sha>` or `@<tag>` in the
consumer `terragrunt.hcl`.

## Commands

```bash
# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy
terragrunt destroy
```

The before-step that spawns `garuda-tunnel` passes
`daemon.auto_stop_idle_seconds = 300`, so a daemon that nobody connects
to for five minutes SIGTERMs itself. Orphan recovery is automatic —
no manual `pkill` needed even if Terragrunt is killed mid-apply, parse-
only commands (`output`, `hclvalidate`) leave the tunnel up, or a
SIGINT skips the `after_hook`. Stale marker files in `$TMPDIR` are
harmless once the daemon exits; the next invocation allocates a fresh
`mktemp -u` name.

## Notes

- Edge workload modules are deployed with `for_each` over the `edges` map.
- Linux workload modules depend only on the same-host backbone module.
- See [module execution model](../../../docs/reference/module-execution-model.md)
  for the compute -> garuda-tunnel -> Helm/k3s workload chain.
- See [routing policy reference](../../../docs/reference/routing-policy.md)
  for `routes` and `pinning_egress` schemas.
