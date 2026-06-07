mock_provider "helm" {}
mock_provider "kubernetes" {}

run "single_hostname_outputs_round_trip" {
  command = plan
  variables {
    namespace           = "gateway-system"
    gateway_class_name  = "traefik"
    cluster_issuer_name = "letsencrypt-prod"
    hostnames = [{
      name             = "hub"
      hostname         = "hub.example.net"
      cert_secret_name = "hub-tls"
    }]
  }
  assert {
    condition     = output.gateway_name == "platform-gateway"
    error_message = "gateway_name must equal local.gateway_name"
  }
  assert {
    condition     = output.gateway_namespace == "gateway-system"
    error_message = "gateway_namespace must equal var.namespace"
  }
}

run "rejects_empty_hostname_list" {
  command = plan
  variables {
    namespace           = "gateway-system"
    gateway_class_name  = "traefik"
    cluster_issuer_name = "letsencrypt-prod"
    hostnames           = []
  }
  expect_failures = [var.hostnames]
}

run "helm_release_values_contain_required_keys" {
  command = plan
  variables {
    namespace           = "gateway-system"
    gateway_class_name  = "traefik"
    cluster_issuer_name = "letsencrypt-prod"
    hostnames = [{
      name             = "hub"
      hostname         = "hub.example.net"
      cert_secret_name = "hub-tls"
    }]
  }
  assert {
    condition     = strcontains(helm_release.gateway.values[0], "\"gatewayName\": \"platform-gateway\"")
    error_message = "helm_release values must contain gatewayName platform-gateway"
  }
  assert {
    condition     = strcontains(helm_release.gateway.values[0], "\"gatewayClassName\": \"traefik\"")
    error_message = "helm_release values must contain gatewayClassName traefik"
  }
  assert {
    condition     = strcontains(helm_release.gateway.values[0], "\"clusterIssuerName\": \"letsencrypt-prod\"")
    error_message = "helm_release values must contain clusterIssuerName"
  }
  assert {
    condition     = strcontains(helm_release.gateway.values[0], "\"hostname\": \"hub.example.net\"")
    error_message = "helm_release values must include configured hostname"
  }
  assert {
    condition     = strcontains(helm_release.gateway.values[0], "\"enableTraefikGatewayProvider\": true")
    error_message = "helm_release values must include the default Traefik provider-enable flag"
  }
}
