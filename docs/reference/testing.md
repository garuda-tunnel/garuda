# Testing Reference

## Testing layers

| Layer           | Tool                              | What it covers                                                |
|-----------------|-----------------------------------|---------------------------------------------------------------|
| Module contract | `tofu test`                       | Variable validation, output shape, mock provider runs         |
| Helm golden     | `helm template` + `run-helm-tests.sh` | Rendered manifest shape for each chart                   |
| Local-stand e2e | `./stand e2e` (pytest)            | End-to-end behaviour of the stack on the local stand          |

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

## Python unit tests

Unit tests for the pure-Python helpers live next to the module they test (there
is no shared pytest configuration; each suite is self-contained):

```bash
# Local-stand helper (examples/local-stand/ansible/files/firezone_device.py)
pytest -q examples/local-stand/ansible/tests/test_firezone_device.py
```

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

## Local-stand e2e tests

The end-to-end suite is `examples/local-stand/e2e/`, run on the stand host with
`./stand e2e`; see [`examples/local-stand/e2e/README.md`](../../examples/local-stand/e2e/README.md).
It is the only e2e suite: cloud deployments get no e2e tests, only a drift check
(`tofu plan -detailed-exitcode` must exit 0 after an apply).

## Local stand

A local Vagrant/libvirt stand reproduces the mini-site topology without cloud
accounts or a public domain: see
[examples/local-stand/README.md](../../examples/local-stand/README.md) for
prerequisites, measured sizing and times, outbound dependencies and reset
semantics. Settled stand design decisions live in [docs/decisions/](../decisions/).

## Running all non-live tests

```bash
pytest -q tests
pytest -q examples/local-stand/ansible/tests
(
  cd examples/local-stand/e2e
  pytest -q -m "not stand" .
)
tofu -chdir=examples/local-stand/garuda test # needs a prepared examples/local-stand/.state/
tofu -chdir=examples/mini-site/garuda test
tofu -chdir=examples/mini-site/infra test
tofu -chdir=modules/garuda_k8s test
tofu -chdir=modules/yc_compute_host test
tofu -chdir=modules/gcp_compute_host test
```
