resource "helm_release" "database" {
  name             = var.name
  namespace        = var.namespace
  create_namespace = false

  repository = "oci://ghcr.io/cloudnative-pg/charts"
  chart      = "cluster"
  version    = var.chart_version

  values = [
    yamlencode({
      # Pin the fullname so the Cluster CR is named exactly var.name; the
      # operator derives the <name>-app Secret and <name>-rw service from it.
      fullnameOverride = var.name
      cluster = {
        instances = 1
        imageName = var.image
        # Apps authenticate as the initdb owner via the -app Secret; the
        # postgres superuser password stays disabled.
        enableSuperuserAccess = false
        # Single instance: a PodDisruptionBudget would block node drains.
        enablePDB = false
        # Helm uninstall (incl. tofu destroy) must skip the Cluster so the
        # operator keeps the PVCs alive; deliberate deletion is kubectl-only
        # (see README).
        annotations = {
          "helm.sh/resource-policy" = "keep"
        }
        storage = {
          size         = var.storage_size
          storageClass = var.storage_class
        }
        initdb = {
          database = var.database
          owner    = var.owner
        }
      }
    })
  ]
}
