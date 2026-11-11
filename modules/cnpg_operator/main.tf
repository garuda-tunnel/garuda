locals {
  namespace = "cnpg-system"
}

resource "helm_release" "cnpg" {
  name             = "cnpg"
  namespace        = local.namespace
  create_namespace = true

  repository = "oci://ghcr.io/cloudnative-pg/charts"
  chart      = "cloudnative-pg"
  version    = var.chart_version

  # The operator ships the Cluster CRDs in this release; waiting for its
  # deployment makes the release applied only once CRDs are live, so
  # cnpg_database Clusters can be created in the same apply.
  wait = true
}

resource "kubernetes_storage_class_v1" "retain" {
  metadata {
    name = "local-path-retain"
  }

  storage_provisioner = "rancher.io/local-path"
  reclaim_policy      = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"

  # The class itself does not need the operator — this edge is what orders
  # every cnpg_database (which consumes storage_class_name, and through it
  # this resource) after the operator release, so the Cluster CRDs and their
  # admission webhook exist before the first Cluster is applied. On destroy
  # the databases go before the operator; the operator must still outlive
  # every database (see README).
  depends_on = [helm_release.cnpg]
}
