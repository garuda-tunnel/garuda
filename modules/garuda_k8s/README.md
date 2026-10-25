# garuda_k8s

Bootstraps one Kubernetes namespace with the shared transport plumbing
required by every Garuda edge workload: namespace, two
`NetworkAttachmentDefinition` resources (`backbone`, `border`), a network
metadata `ConfigMap`, and optionally the Multus CNI DaemonSet.

The module is a thin wrapper over `helm_release` rendering the bundled
chart at `${path.module}/charts/garuda`.

## Inputs

| Variable          | Default     | Description |
|-------------------|-------------|-------------|
| `namespace`       | `"garuda"`  | DNS-1123 label for the Kubernetes namespace. |
| `backbone_subnet` | (required)  | CIDR for the `backbone` NAD's host-local IPAM, e.g. `10.42.0.0/24`. |
| `border_subnet`   | (required)  | CIDR for the `border` NAD's host-local IPAM, e.g. `10.43.0.0/24`. |
| `install_cni`     | `true`      | When `true`, install Multus from vendored manifests. Set `false` when CNI is pre-installed. |

## Outputs

| Output              | Description |
|---------------------|-------------|
| `namespace`         | Echo of `var.namespace`. Pass to `modules/wireguard/kube`. |
| `backbone_nad_name` | Static value `"backbone"`. |
| `border_nad_name`   | Static value `"border"`. |

## Providers

The module declares only `required_providers`. The caller must pass aliased
`helm` and `kubernetes` providers via the `providers` block:

```hcl
module "garuda_k8s_pt" {
  source = "../../../modules/garuda_k8s"
  providers = {
    helm       = helm.pt
    kubernetes = kubernetes.pt
  }
  backbone_subnet = "10.42.0.0/24"
  border_subnet   = "10.43.0.0/24"
}
```

## Multus sizing and pod-reaper scope

- The Multus daemon (`kube-multus`) runs with a 256Mi memory limit and no CPU
  limit (request `100m` / `96Mi`). Upstream's `100m` / `50Mi` is too small for
  a node with several Multus-attached pods: after a reboot the daemon thrashes
  its page cache, is CPU-throttled, misses its API deadlines, and no pod gets a
  sandbox (issue #179). Measured on a hub: steady 67–68Mi (about 11Mi anon),
  peak 75Mi, so 256Mi is ≈3.4× peak.
- The pod reaper only reaps pods that are unready longer than
  `podReaper.maxUnready` **and** have a container (init containers included) in
  one of `podReaper.containerStatuses` (`CrashLoopBackOff`, `Error`,
  `StartError`, `CreateContainerError`). Pods still in `ContainerCreating` /
  `PodInitializing` (no sandbox yet) are not reaped: replacing them only adds
  CNI load. Pods that start without their Multus interfaces and crash-loop are
  still replaced (ADR 0002). A pod that is `Running` but never Ready is no
  longer reaped.
- The reaper is scoped to pods labelled `app.kubernetes.io/part-of=garuda`. The
  `garuda-multus-ready` Helm hook pod deliberately does not carry that label;
  keep any new hook pod unlabelled the same way.

## What this module does NOT do

- No workload pods. See `modules/wireguard/kube` for the WireGuard endpoint.
- No host CNI binaries install on the node — that is `modules/k3s_cloud_init`'s job. This module only installs the in-cluster Multus DaemonSet.
- No `hostNetwork` for Garuda workload pods. The Multus CNI DaemonSet installed when `install_cni = true` does use `hostNetwork` because that is how the CNI plugin binary is delivered to the kubelet; that exception is scoped to `kube-system` CNI installation, not application workloads.
- No kubeconfig fetch. Consumers fetch `/etc/rancher/k3s/k3s.yaml` over SSH and rewrite the apiserver `server:` URL to a local SSH forward — see the consumer Terragrunt unit's `before_hook` (the `examples/mini-site/garuda` consumer uses `garuda-tunnel` for this).
- No cluster-init / multi-node clustering. Each edge runs an independent single-node k3s server.
