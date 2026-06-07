locals {
  gateway_name = "platform-gateway"
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "gateway-api-platform"
    }
  }
}

resource "helm_release" "gateway" {
  name             = local.gateway_name
  namespace        = kubernetes_namespace_v1.this.metadata[0].name
  create_namespace = false
  chart            = "${path.module}/charts/platform-gateway"

  values = [
    yamlencode({
      gatewayName                  = local.gateway_name
      gatewayClassName             = var.gateway_class_name
      clusterIssuerName            = var.cluster_issuer_name
      hostnames                    = var.hostnames
      labels                       = var.labels
      enableTraefikGatewayProvider = var.enable_traefik_gateway_provider
    })
  ]
}
