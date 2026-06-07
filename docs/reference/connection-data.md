# connection_data Contract

The `connection_data` object is the normalized SSH transport and authentication
contract exported by compute modules (`yc_compute_host`, `gcp_compute_host`).
It is consumed by `garuda-tunnel` to open SSH tunnels and fetch k3s kubeconfigs,
and is also available for direct SSH access by operators.

## Shape

```hcl
connection_data = {
  host                 = string           # SSH hostname or IP
  user                 = string           # SSH user
  connection           = string           # Connection type (e.g. "ssh")
  network_os           = string           # OS type (e.g. "linux")
  password             = optional(string) # SSH password (mutually exclusive with ssh_private_key*)
  ssh_private_key_file = optional(string) # Path to private key file
  ssh_private_key      = optional(string) # Inline private key PEM
  instance_token       = string           # Opaque invalidation discriminator
}
```

`ssh_private_key` and `ssh_private_key_file` are mutually exclusive — provide at
most one.

## instance_token

`instance_token` is a mandatory opaque string. By convention, compute modules
populate it with a stable cloud instance identifier (Yandex Cloud
`yandex_compute_instance.id`, GCP `google_compute_instance.self_link`).

A change in `instance_token` signals that the VM has been recreated. Consumers
that cache state (such as `garuda-tunnel`) can detect this and invalidate cached
kubeconfigs, forcing a fresh fetch from the new host.

Do not set `instance_token` manually unless you are writing a compute module.

## Flow

```
compute module (yc_compute_host / gcp_compute_host)
  -> outputs connection_data with instance_token = cloud instance ID
  -> garuda-tunnel (SSH into host, fetch /etc/rancher/k3s/k3s.yaml, patch server:)
  -> patched kubeconfig materialized at local path
  -> garuda/ providers.tf reads kubeconfig path from tunnel state JSON
  -> helm / kubernetes Terraform providers use the materialized kubeconfig
```

The `garuda/` unit reads kubeconfig paths from the JSON state file written by
`garuda-tunnel` (`var.tunnel_path`). It does not consume `connection_data` directly;
`connection_data` is passed to `garuda-tunnel` via the Terragrunt stand
configuration, not through Terraform inputs of the `garuda/` unit.

## Related

- [Module execution model](module-execution-model.md)
- [Prerequisites — garuda-tunnel](../getting-started/prerequisites.md#garuda-tunnel-and-kubeconfigs)
