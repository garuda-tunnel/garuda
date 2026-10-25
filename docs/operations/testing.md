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
# garuda-tunnel/wireguard: tofu -chdir=tunnel test && tofu -chdir=kube test && tofu -chdir=routeros test
# garuda-tunnel/firezone:  tofu -chdir=kube test
# garuda-tunnel/router:    tofu -chdir=kube test
# garuda-tunnel/border-router: tofu test
```

## Post-apply health check

After a successful apply a second plan must be empty
(`tofu -chdir=examples/mini-site/garuda plan -detailed-exitcode`, exit code 0).
The only end-to-end suite is the pytest suite of the local stand,
[`examples/local-stand/e2e/README.md`](../../examples/local-stand/e2e/README.md).

## Further reading

- [Testing reference](../reference/testing.md) — full layer description.
