# cnpg_operator

Installs the [CloudNativePG](https://cloudnative-pg.io) operator once per hub
cluster and creates the shared `local-path-retain` StorageClass used by every
CNPG database module. Databases themselves live in
[`../cnpg_database`](../cnpg_database), one release per app namespace.

The StorageClass is `Retain` because CNPG sets the Cluster as the owner of its
PVCs: deleting a Cluster (for example uninstalling an app's database release)
cascade-deletes the PVCs, and with k3s's default `local-path` (`Delete`)
that would destroy the data volume. `Retain` keeps it for re-import.

## Inputs

| Variable | Type | Default | Description |
|---|---|---|---|
| `chart_version` | string | (required) | `cloudnative-pg` operator chart version from `oci://ghcr.io/cloudnative-pg/charts`. No default — pin it at the call site with a `# renovate: datasource=docker depName=ghcr.io/cloudnative-pg/charts/cloudnative-pg` annotation. |

## Outputs

| Output | Description |
|---|---|
| `storage_class_name` | Name of the shared Retain StorageClass (`local-path-retain`). |

## Providers

```hcl
module "cnpg_operator" {
  source = "../../../modules/cnpg_operator"
  # renovate: datasource=docker depName=ghcr.io/cloudnative-pg/charts/cloudnative-pg
  chart_version = "0.29.1"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  depends_on = [module.garuda_k8s_hub]
}
```

The release uses `wait = true` so the operator deployment (and its Cluster
CRDs) are live before the release counts as applied — `cnpg_database` Clusters
can then be created in the same `tofu apply`.

## Ordering and lifecycle

Callers must wire `storage_class = module.cnpg_operator.storage_class_name`.
The output derives from the StorageClass, which in turn depends on the
operator release — that edge is what orders every `cnpg_database` after it
(Cluster CRDs and their admission webhook exist before the first Cluster) and
destroys the databases before it.

The operator must **outlive every database**. Uninstalling the release does not
remove the CRDs (the chart marks them `helm.sh/resource-policy: keep`, verified on
chart `0.29.1`), so the `Cluster` resources and the PVCs survive — but with no
operator the Clusters go unreconciled: no failover, no Secret handling, and a Postgres pod
that dies is not recreated. Never destroy this module while databases exist.

## Pre-existing `local-path-retain`

If the StorageClass already exists on the cluster (created by hand), import it
instead of letting Terraform adopt-over: `tofu import` the resource
(`kubernetes_storage_class_v1.retain` in this module) with the class name as
ID. Its fields (provisioner, reclaim policy, binding mode) are immutable in
Kubernetes — changing them requires delete + recreate, which the import path
avoids.

## What this module does NOT do

- Does not create any `Cluster` or database — that is `cnpg_database`.
- Does not configure monitoring, pooling or backups.
- Does not change node storage: `local-path-retain` reuses k3s's built-in
  `rancher.io/local-path` provisioner with a different reclaim policy.
