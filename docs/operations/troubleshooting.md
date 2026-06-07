# Troubleshooting

## Quick symptom table

| Symptom                                          | First command                                                                            |
|--------------------------------------------------|------------------------------------------------------------------------------------------|
| OSPF neighbor does not come up                   | `kubectl -n garuda exec <pod> -c frr-sidecar -- vtysh -c 'show ip ospf neighbor'`       |
| Transit route missing on a consumer              | `kubectl -n garuda exec <pod> -c <container> -- ip route show table 201`                 |
| WireGuard tunnel is down                         | `kubectl -n garuda exec <wg-pod> -c wg -- wg show`                                      |
| Firezone OIDC not reconciled / sidecar not Ready | `kubectl -n garuda logs <firezone-pod> -c oidc-reconcile` — expect "reconcile applied" → "minted token deleted" → "idling"; if not Ready, `/tmp/oidc-reconcile-ok` was not written |
| Firezone API or web UI not responding            | `kubectl -n garuda logs <firezone-pod> -c firezone`; check `fz_admin` credentials       |
| RouterOS cannot reach WireGuard tunnel endpoint  | Re-apply the `garuda/` unit — see [RouterOS DHCP drift](#routeros-dhcp-drift)            |
| `ipt_server` geo/domain routing not working      | `kubectl -n garuda logs <ipt-server-pod> -c ipt-server`; check `routes` config          |
| `ipt_server` pinning not engaging                | Check `pinning_egress` is non-empty; verify client source IP routing                     |
| Pod in CrashLoopBackOff                          | `kubectl -n garuda describe pod <pod>`; `kubectl -n garuda logs <pod> -c <container>`   |
| Helm release stuck / rollback needed             | `helm -n garuda status <release>`; `helm -n garuda rollback <release>`                   |
| garuda-tunnel / kubeconfig not materialized      | Re-run `uvx garuda-tunnel start`; verify `var.tunnel_path` points at the JSON output    |

## OSPF and transit routing

```bash
# Neighbor state on any FRR sidecar
kubectl -n garuda exec <pod> -c frr-sidecar -- vtysh -c 'show ip ospf neighbor'

# OSPF external LSA database (check for ipt_server tag=100)
kubectl -n garuda exec <pod> -c frr-sidecar -- vtysh -c 'show ip ospf database external'

# Transit route table on a consumer
kubectl -n garuda exec <pod> -c <workload-container> -- ip route show table 201

# FRR sidecar logs
kubectl -n garuda logs <pod> -c frr-sidecar
```

## WireGuard

```bash
# WireGuard interface state
kubectl -n garuda exec <wg-pod> -c wg -- wg show

# Check peer handshake time
kubectl -n garuda exec <wg-pod> -c wg -- wg show <ifname> latest-handshakes
```

## ipt_server

```bash
# Follow logs
kubectl -n garuda logs -f <ipt-server-pod> -c ipt-server

# nftables marks (inside the pod network namespace)
kubectl -n garuda exec <ipt-server-pod> -c ipt-server -- nft list ruleset
```

## Firezone

```bash
# Firezone pod logs
kubectl -n garuda logs <firezone-pod> -c firezone

# OIDC reconcile sidecar (expected sequence: applied -> token deleted -> idling)
kubectl -n garuda logs <firezone-pod> -c oidc-reconcile
```

## RouterOS DHCP drift

RouterOS's DHCP client can rewrite `default-route-tables`, breaking the WireGuard
endpoint bypass route. Re-apply the `garuda/` unit so the RouterOS module refreshes
the bypass resources:

```bash
tofu -chdir=examples/mini-site/garuda plan
tofu -chdir=examples/mini-site/garuda apply
```

## Observability notes

- All Garuda workload pods log to stdout; use `kubectl logs` with `-c <container>`.
- FRR state: use `vtysh -c '...'` inside the `frr-sidecar` container of the pod.
- `ipt_server` logs to stdout in the `ipt-server` container.
- Helm release status: `helm -n garuda list` to list all releases;
  `helm -n garuda status <release>` for per-release detail.
