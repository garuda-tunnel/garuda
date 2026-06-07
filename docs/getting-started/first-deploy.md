# First Deploy

This guide walks through deploying the `examples/mini-site` reference topology
for the first time.

## Before you start

Complete all items in [prerequisites](prerequisites.md):

- OpenTofu, Terragrunt, SOPS, and `garuda-tunnel` installed.
- Cloud provider credentials configured (Yandex Cloud for hub, GCP for edges).
- SSH key generated and ready.
- Container images available from `ghcr.io/garuda-tunnel/garuda-*` (default; override
  image variables if using a custom registry).

## Step 1: Prepare inputs

Copy and fill in the variable template:

```bash
cp examples/mini-site/inputs.tfvars.yaml.example examples/mini-site/inputs.tfvars.yaml
```

Replace every placeholder value:

- `base_domain` — your actual domain (must be a real domain for cert-manager ACME).
- `env_slug` — short identifier for this environment.
- `edges.*.hub_cidr` / `edges.*.peer_cidr` — your WireGuard address ranges.
- `routeros.management_host` — your RouterOS device IP.
- `operator_ssh_keys` — your real SSH public key.
- `cert_manager_email` — operational email for Let's Encrypt contact.

Do not commit `inputs.tfvars.yaml` to version control if it contains real values.
Use SOPS encryption for production inputs.

## Step 2: Apply infra

The `infra/` unit provisions compute VMs, DNS records, and k3s cloud-init:

```bash
tofu -chdir=examples/mini-site/infra init
tofu -chdir=examples/mini-site/infra plan
tofu -chdir=examples/mini-site/infra apply
```

Expected: hub VM (Yandex Cloud) and edge VMs (GCP) are running with k3s bootstrapped
via cloud-init. DNS records are created. SSH access is available.

## Step 3: Start garuda-tunnel

Before applying `garuda/`, start `garuda-tunnel` to open SSH tunnels and
materialize per-node kubeconfigs:

```bash
uvx garuda-tunnel start --config <your-stand-tunnel-config>
```

`garuda-tunnel` writes a JSON state file. Set `var.tunnel_path` in your Terragrunt
configuration to point at this file. Nodes whose kubeconfig has not been materialized
will use the inert provider branch (no live API calls).

## Step 4: Apply garuda

```bash
tofu -chdir=examples/mini-site/garuda init
tofu -chdir=examples/mini-site/garuda plan
tofu -chdir=examples/mini-site/garuda apply
```

This deploys in dependency order:

1. `garuda_k8s` namespace bootstrap on hub and each edge (Multus, Whereabouts,
   backbone/border NADs).
2. `wireguard/kube` deployments on hub and each edge.
3. `wireguard/routeros` on the RouterOS device.
4. `cert_manager` and `k8s_gateway_bootstrap` on hub.
5. `firezone/kube` and `ipt_server/kube` on hub.
6. `border_router` on hub.

**Note on Firezone OIDC.** OIDC providers are reconciled automatically by the
`oidc-reconcile` sidecar in the `firezone/kube` module on every apply and pod
recreation — no second apply is needed.

Expected: all workloads are running. OSPF adjacencies are up. WireGuard tunnels
are active. Firezone is reachable at the configured FQDN with a valid TLS cert.

## Step 5: Run smoke tests

```bash
ansible-playbook examples/mini-site/smoke/z2g.yml
```

See [smoke testing runbook](../operations/smoke-testing.md) for the full phase
description.

## Update

To update workloads after a code change:

```bash
tofu -chdir=examples/mini-site/garuda plan
tofu -chdir=examples/mini-site/garuda apply
```

Terraform detects changes and re-applies only affected modules. Helm releases are
upgraded in place; Kubernetes resources are patched.

## Destroy

Destroy in reverse order:

```bash
tofu -chdir=examples/mini-site/garuda destroy
tofu -chdir=examples/mini-site/infra destroy
```

## Further reading

- [Deploy / update / destroy runbook](../operations/deploy-update-destroy.md)
- [Troubleshooting](../operations/troubleshooting.md)
- [Reference topology](reference-topology.md)
