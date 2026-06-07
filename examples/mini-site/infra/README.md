# mini-site / infra

This Terragrunt unit provisions infrastructure and exports the connection facts
that the `garuda/` unit consumes.

## Responsibilities

- Provision cloud compute (hub VM and edge VMs via `yc_compute_host` /
  `gcp_compute_host` or equivalent).
- Register DNS records for hub and edges via the `cloudflare_*` outputs.
- Bootstrap RouterOS tunnel parameters.

## Outputs consumed by garuda/

| Output                 | Type                    | Used by                                       |
|------------------------|-------------------------|-----------------------------------------------|
| `connection_data_hub`  | `connection_data` object | consumed by garuda-tunnel + the k3s hub workload modules    |
| `connection_data_edges`| map of `connection_data` | consumed by garuda-tunnel + the k3s edge workload modules   |
| `cloudflare_hub`       | DNS record object       | hub DNS facts                                 |
| `cloudflare_edges`     | map of DNS record objects | edge DNS facts                              |
| `routeros`             | RouterOS bootstrap object | `wireguard/routeros` module                 |

## Commands

```bash
# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy (run garuda/ destroy first)
terragrunt destroy
```

## Notes

- `connection_data.instance_token` is populated by the compute module from the
  cloud instance identity. Do not set it manually.
- `env_slug` is a mandatory input for compute modules in shared-namespace
  deployments. See [modules reference](../../../docs/reference/modules.md).
