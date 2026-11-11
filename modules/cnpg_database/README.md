# cnpg_database

One CloudNativePG `Cluster` (single instance) in an existing app namespace, as its own
Helm release of the official `cluster` chart (`oci://ghcr.io/cloudnative-pg/charts`),
separate from the app so uninstalling the app never touches the database. Needs the
operator and the Retain StorageClass from [`../cnpg_operator`](../cnpg_operator).

## Contract

- `output.secret_name` (`<name>-app`) is the operator-generated Secret with the keys
  `host`, `port`, `dbname`, `username`, `password`; the app consumes it (Firezone
  `database_secret_name`). The app connects as the initdb owner; the `postgres`
  superuser stays disabled.
- `storage_class` must be a Retain class (`module.cnpg_operator.storage_class_name`):
  CNPG owns the Cluster's PVCs, so a Delete class destroys the volume with the Cluster.
- The Cluster carries `helm.sh/resource-policy: keep` (see "Uninstall keeps the database").
- `enablePDB` is false: with one instance a PodDisruptionBudget only blocks node drains.
- Firezone's extensions (`pgcrypto`, `btree_gist`, `citext`) are trusted and created by
  the owner during migrations; there is no `postInitApplicationSQL`.

## No readiness wait

Helm's `wait` does not understand the `Cluster` CR and the module adds no wait logic.
CNPG creates `<name>-app` early, so the app pod starts, fails to connect and retries; an
apply before the operator reconciled the Cluster leaves it in
`CreateContainerConfigError`, which the kubelet retries. Do not "fix" it with sleeps.

## Uninstall keeps the database

Uninstalling the release (or `tofu destroy`) leaves the Cluster and its PVCs with the
operator. To delete deliberately:

    kubectl -n <namespace> delete cluster <name>

With the Retain class the PV then lingers as `Released`; clear its `spec.claimRef` to make
it `Available` again.

## Durability

The bytes live where the platform puts the StorageClass: the k3s local-path base directory
(`default-local-storage-path`, default `/var/lib/rancher/k3s/storage`), which a site points at
its backed-up data disk (infra unit `k3s_config`; the local stand uses an `/opt/garuda/...`
path). The platform's data-disk backup is the only copy, so a lost disk is a lost database.
A VM rebuild loses the k3s datastore (PV, PVC and Cluster objects) in every case; the
directory survives only if the data disk does. After a rebuild re-attach the old volume to a
new Cluster by hand: firezone-internal `docs/operations/operator-runbook-cnpg-migration.md`,
section 9. Object-store backups were removed as unused (history at garuda-internal
`b12124c4`); re-add them as a separate task when needed.

## Inputs

| Variable | Type | Default | Description |
|---|---|---|---|
| `namespace` | string | (required) | Existing namespace for the Cluster and its Secret; created by the app module, never here. |
| `name` | string | `postgres` | Cluster and release name; the operator derives `<name>-app` and `<name>-rw`. DNS-1123, at most 50 characters so derived names stay under 63. |
| `database` | string | (required) | Database created by `bootstrap.initdb`. |
| `owner` | string | (required) | Owning role; its credentials go into the `<name>-app` Secret. |
| `storage_size` | string | `2Gi` | PVC size (Kubernetes quantity). |
| `storage_class` | string | `local-path-retain` | Retain StorageClass, see Contract. |
| `image` | string | (required) | Postgres image, `tag@digest`-pinned. The org Renovate regex cannot parse such tags, so mark the pin with a `# shortcut:` hand-bump note instead of a `# renovate:` annotation. |
| `chart_version` | string | (required) | `cluster` chart version, pinned with a `# renovate: datasource=docker depName=ghcr.io/cloudnative-pg/charts/cluster` annotation; empty is rejected (it would install the latest chart). |

## Outputs

| Output | Description |
|---|---|
| `cluster_name` | `<name>`: Cluster and release name. |
| `secret_name` | `<name>-app`, the operator-generated application Secret. |

## Usage

```hcl
module "firezone_db" {
  source = "../../../modules/cnpg_database"

  namespace = kubernetes_namespace_v1.firezone.metadata[0].name
  database  = "firezone"
  owner     = "firezone"
  # shortcut: tag@digest pin bumped by hand (org Renovate regex has no digest capture).
  image = "ghcr.io/cloudnative-pg/postgresql:17.11-202611020810-standard-trixie@sha256:4d0aac315c4d8c3202252bd06fea83b16951cc57234a7b610eeaa382ff4482d0"
  # renovate: datasource=docker depName=ghcr.io/cloudnative-pg/charts/cluster
  chart_version = "0.9.0"
  storage_class = module.cnpg_operator.storage_class_name

  providers = {
    helm = helm.hub
  }
}
```

## What this module does NOT do

- Install the operator or the StorageClass (`cnpg_operator`) or create the namespace.
- Wait for readiness or run post-init SQL.
- Back up to an object store, restore, or run replicas or pooling: one instance, and the
  Retain class only keeps a deleted Cluster's volume around.
