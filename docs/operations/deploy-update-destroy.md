# Deploy / Update / Destroy

## First-time deploy

1. Complete [prerequisites](../getting-started/prerequisites.md).
2. Prepare inputs (copy `inputs.tfvars.yaml.example`, fill in values).
3. Start `garuda-tunnel` so kubeconfig paths are available for provider configuration.
4. Apply `infra/` first, then `garuda/`.

```bash
tofu -chdir=examples/mini-site/infra init
tofu -chdir=examples/mini-site/infra plan
tofu -chdir=examples/mini-site/infra apply

# Start garuda-tunnel (adjust config path for your stand)
uvx garuda-tunnel start --config <tunnel-config>

tofu -chdir=examples/mini-site/garuda init
tofu -chdir=examples/mini-site/garuda plan
tofu -chdir=examples/mini-site/garuda apply
```

## Update

### Terraform module change

Edit module inputs, Helm chart values, or image references, then apply:

```bash
tofu -chdir=examples/mini-site/garuda plan
tofu -chdir=examples/mini-site/garuda apply
```

Terraform detects changes and upgrades only affected Helm releases. Kubernetes
resources are patched in place; pods are rolled by Helm when relevant values change.

### Container image update

Update the image variable (e.g. `var.wireguard_image`) to point at a new tag and
apply. The `helm_release` detects the values change and triggers a rolling update
of the affected Deployment.

### RouterOS change

Edit the relevant `wireguard/routeros` module inputs and apply:

```bash
tofu -chdir=examples/mini-site/garuda plan
tofu -chdir=examples/mini-site/garuda apply
```

### RouterOS DHCP drift reconcile

RouterOS's DHCP client can occasionally rewrite `default-route-tables` in a way
that breaks the WireGuard endpoint bypass route. Re-apply the `garuda/` unit so
the RouterOS module refreshes the bypass resources:

```bash
tofu -chdir=examples/mini-site/garuda plan
tofu -chdir=examples/mini-site/garuda apply
```

## Destroy

Destroy in reverse unit order:

```bash
tofu -chdir=examples/mini-site/garuda destroy
tofu -chdir=examples/mini-site/infra destroy
```

Helm releases are uninstalled first; Kubernetes resources are cleaned up by the
Helm provider. The `garuda_k8s` namespace bootstrap (Multus/Whereabouts DaemonSets
and NADs) is removed last within each cluster.

## Post-apply health check

Run the smoke playbook once `garuda-tunnel` is active and the apply succeeded:

```bash
ansible-playbook examples/mini-site/smoke/z2g.yml
```

## Further reading

- [Smoke testing](smoke-testing.md)
- [Troubleshooting](troubleshooting.md)
- [First deploy guide](../getting-started/first-deploy.md)
