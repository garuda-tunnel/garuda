# Smoke Testing

Smoke tests verify end-to-end network reachability after apply. They are separate
from module contract tests (which use mock providers and `tofu test`) and from
FRR sidecar unit tests.

## In-repo reference smoke

The in-repo reference topology has its smoke playbook at:

```
examples/mini-site/smoke/z2g.yml
```

The playbook bootstraps its inventory from Terraform outputs (fetched via
`tofu output -json ansible_smoke_inventory`), then runs verification phases
against the live stand.

```bash
ansible-playbook examples/mini-site/smoke/z2g.yml
```

The default run (without `-e allow_apply=yes`) executes all phases except the
gated apply phase. Individual phases can be targeted with `--tags phase_N`.

## What smoke tests verify

A complete smoke run should verify:

- WireGuard tunnel connectivity (hub-to-edge, hub-to-RouterOS).
- OSPF neighbor adjacency on all FRR sidecars.
- Transit route propagation (table 201 populated on Firezone and RouterOS consumers).
- `ipt_server` routing: geo rule (country match), domain rule (regex match),
  CIDR rule, and pinning egress if enabled.
- Firezone VPN client reachability and API response.
- Kubernetes workload health (all pods Running/Ready).
- RouterOS LAN reachability through the WireGuard tunnel.

## Running individual checks manually

```bash
# OSPF neighbor state on a k3s pod with FRR sidecar
kubectl -n garuda exec <wg-pod> -c frr-sidecar -- vtysh -c 'show ip ospf neighbor'

# Transit route table inside a pod
kubectl -n garuda exec <pod> -c <workload-container> -- ip route show table 201

# ipt_server logs
kubectl -n garuda logs <ipt-server-pod> -c ipt-server

# WireGuard interface state
kubectl -n garuda exec <wg-pod> -c wg -- wg show

# Firezone OIDC reconcile sidecar
kubectl -n garuda logs <firezone-pod> -c oidc-reconcile
```

## Further reading

- [Troubleshooting](troubleshooting.md)
- [Testing reference](../reference/testing.md)
- [Deploy / update / destroy](deploy-update-destroy.md)
