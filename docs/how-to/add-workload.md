# How to Add a Workload

This guide shows the minimal path to add a new Garuda workload as a Kubernetes
(k3s) deployment managed by a Terraform module with a Helm chart.

## Overview

Garuda workloads follow the same pattern regardless of what they do:

1. A Terraform module with a bundled Helm chart under `modules/<name>/charts/<name>/`.
2. A structured `ospf` object input (optional) that the FRR sidecar reads.
3. The `frr-sidecar` Helm chart from `oci://ghcr.io/garuda-tunnel/charts` as a
   `dependencies:` entry if the workload needs OSPF.
4. `depends_on = [module.garuda_k8s_<cluster>]` in the call site.

> **Historical note.** Prior to the k3s migration, workloads were added as Ansible
> roles using `docker-compose` and `modules/linux_apply`. That pattern was removed.
> The current pattern is a Terraform module with a Helm chart.

## Step 1: Write the Terraform module

Create `modules/my_workload/` with the standard layout:

```
modules/my_workload/
  main.tf         # helm_release resource
  variables.tf    # inputs including ospf, namespace, image
  outputs.tf
  versions.tf
  charts/
    my-workload/
      Chart.yaml  # declare frr-sidecar dependency if OSPF is needed
      templates/
        deployment.yaml
      values.yaml
  image/          # Dockerfile and build context (if module ships its own image)
  tests/          # tofu tests + helm golden tests
```

### Chart.yaml (if OSPF sidecar is needed)

```yaml
name: my-workload
version: 0.1.0
dependencies:
  - name: frr-sidecar
    version: 0.1.0
    repository: "oci://ghcr.io/garuda-tunnel/charts"
```

The consumer `helm_release` must set `dependency_update = true` so Helm resolves
the OCI dependency at apply time. Do not vendor the library chart or copy its
container spec inline.

### main.tf

```hcl
resource "helm_release" "my_workload" {
  name             = "my-workload"
  namespace        = var.namespace
  chart            = "${path.module}/charts/my-workload"
  dependency_update = true

  set {
    name  = "image"
    value = var.image
  }

  # Pass the ospf object as a JSON blob to the chart if FRR sidecar is needed.
  set {
    name  = "ospf"
    value = jsonencode(var.ospf)
  }
}
```

### deployment.yaml (excerpt)

Use the library chart's named templates to include the FRR sidecar:

```yaml
spec:
  template:
    spec:
      containers:
        - name: my-workload
          image: {{ .Values.image }}
        {{- include "frr-sidecar.container" . | nindent 8 }}
      volumes:
        {{- include "frr-sidecar.volume" . | nindent 8 }}
```

Do not inline a copy of the FRR sidecar container spec. Do not add local helpers
that duplicate `frr-sidecar.frrConf` rendering logic.

## Step 2: Wire the call site with correct depends_on

In `examples/mini-site/garuda/main.tf`:

```hcl
module "my_workload_hub" {
  source = "./modules/my_workload"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace = module.garuda_k8s_hub.namespace
  image     = var.my_workload_image
  ospf = {
    router_id          = var.ospf_router_ids.my_workload
    interfaces         = ["backbone"]
    passive_interfaces = []
    default_originate  = false
    redistribute       = []
  }

  depends_on = [module.garuda_k8s_hub]
}
```

`depends_on` must reference only the same-cluster `garuda_k8s` module. Do not add
cross-cluster dependencies. See [module execution model](../reference/module-execution-model.md).

If the workload needs OSPF, also add new explicit provider aliases in `providers.tf`
(one `helm` + one `kubernetes` alias per cluster the workload targets).

## Step 3: Apply

```bash
tofu -chdir=examples/mini-site/garuda plan
tofu -chdir=examples/mini-site/garuda apply
```

The FRR sidecar starts in the same pod and speaks OSPF on the declared interfaces
once the pod is running.

## Step 4: Add a container image (optional)

If the module ships its own image, place the Dockerfile in the component's own
external repository (e.g. `garuda-tunnel/garuda-<name>`). The umbrella no longer
builds or publishes workload images — each component repo owns its own image
publishing pipeline.

The published image should follow the naming convention
`ghcr.io/garuda-tunnel/garuda-<name>` and be defaulted in the module's `variables.tf`.

## Further reading

- [Module execution model](../reference/module-execution-model.md)
- [Architecture — FRR sidecars](../concepts/architecture.md#frr-sidecars)
- [`wireguard/kube` README](https://github.com/garuda-tunnel/garuda-wireguard/blob/main/kube/README.md)
