# Testing Reference

## Testing layers

| Layer           | Tool                              | What it covers                                                |
|-----------------|-----------------------------------|---------------------------------------------------------------|
| Module contract | `tofu test`                       | Variable validation, output shape, mock provider runs         |
| Helm golden     | `helm template` + `run-helm-tests.sh` | Rendered manifest shape for each chart                   |
| Live smoke      | `ansible-playbook z2g.yml`        | End-to-end network reachability after apply                   |

## Module tests (tofu test)

Each module that uses mock providers has `.tftest.hcl` files under `modules/*/tests/`
or `examples/*/tests/`.

```bash
# Run umbrella module contract tests
tofu -chdir=examples/mini-site/garuda test
tofu -chdir=examples/mini-site/infra test
tofu -chdir=modules/garuda_k8s test
tofu -chdir=modules/yc_compute_host test
tofu -chdir=modules/gcp_compute_host test

# Component module tests run in their external repos (not in the umbrella)
```

Module tests use mock providers so they do not require cloud credentials, a live
k3s cluster, or a running `garuda-tunnel`. They verify:

- Variable validation rules (e.g. `env_slug` format, `pinning_egress` key format).
- Output shapes (e.g. `wireguard/tunnel` emits `tunnel_name` and `kernel_ifname`).
- Wiring logic (e.g. `examples/mini-site/garuda` wires the correct modules with
  the correct provider aliases for hub and each edge).

## Helm golden tests

Charts that ship with golden manifests validate rendering with:

```bash
# In a module's test directory (adjust path)
helm dependency update modules/<name>/charts/<chart>
helm template <release> modules/<name>/charts/<chart> -f modules/<name>/tests/fixtures/<values>.yaml \
  | diff - modules/<name>/tests/golden/<manifest>.yaml
```

Modules that include a `run-helm-tests.sh` script call `helm dependency update`
before `helm template` to ensure the `frr-sidecar` library chart is resolved.

## Live smoke tests

Live smoke tests require a deployed stand with `garuda-tunnel` running. The public
reference smoke entrypoint is `examples/mini-site/smoke/z2g.yml`.

```bash
ansible-playbook examples/mini-site/smoke/z2g.yml
```

The playbook bootstraps its host inventory from `tofu output -json` and runs
verification phases against the live stand. See the smoke README and
[smoke testing runbook](../operations/smoke-testing.md).

## Running all non-live tests

```bash
tofu -chdir=examples/mini-site/garuda test
tofu -chdir=examples/mini-site/infra test
tofu -chdir=modules/garuda_k8s test
tofu -chdir=modules/yc_compute_host test
tofu -chdir=modules/gcp_compute_host test
```
