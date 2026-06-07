# Testing Runbook

## Run all non-live tests

```bash
# Module contract tests (umbrella)
tofu -chdir=examples/mini-site/garuda test
tofu -chdir=examples/mini-site/infra test
tofu -chdir=modules/garuda_k8s test
tofu -chdir=modules/yc_compute_host test
tofu -chdir=modules/gcp_compute_host test

# Component module tests (run in their respective external repos)
# garuda-tunnel/garuda-wireguard: tofu -chdir=tunnel test && tofu -chdir=kube test && tofu -chdir=routeros test
# garuda-tunnel/garuda-firezone:  tofu -chdir=kube test
# garuda-tunnel/garuda-router:    tofu -chdir=kube test
# garuda-tunnel/garuda-border-router: tofu test
```

## Run live smoke

After a successful apply and with `garuda-tunnel` running:

```bash
ansible-playbook examples/mini-site/smoke/z2g.yml
```

`z2g.yml` is the public smoke entrypoint. It bootstraps its inventory from
`tofu output -json` and runs verification phases against the live stand.
See `examples/mini-site/smoke/README.md` for the expected checks.

## Post-apply health check

Use the smoke playbook (`z2g.yml`) once the apply completes.

## Further reading

- [Testing reference](../reference/testing.md) — full layer description.
- [Smoke testing](smoke-testing.md) — what smoke tests cover.
