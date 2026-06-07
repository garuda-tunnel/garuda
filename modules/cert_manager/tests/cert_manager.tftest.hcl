mock_provider "helm" {}

variables {
  email                         = "ops@example.net"
  acme_server                   = "https://acme-staging-v02.api.letsencrypt.org/directory"
  allow_reserved_contact_domain = true
}

run "helm_release_is_cert_manager" {
  command = plan

  assert {
    condition     = helm_release.cert_manager.name == "cert-manager"
    error_message = "helm release name must be cert-manager"
  }

  assert {
    condition     = helm_release.cert_manager.namespace == "cert-manager"
    error_message = "helm release namespace must be cert-manager"
  }

  assert {
    condition     = strcontains(helm_release.cert_manager.values[0], "enableGatewayAPI")
    error_message = "cert-manager must enable Gateway API support (config.enableGatewayAPI) for gateway-shim controller"
  }
}

run "issuer_manifest_uses_traefik_http01" {
  command = plan

  # The ClusterIssuer kind and traefik class live in the subchart template,
  # not in the helm_release values[] (which only hold input values passed by
  # the module). Assert on the chart template file directly — it is the
  # single source of truth for what gets rendered on apply.
  assert {
    condition     = strcontains(file("${path.module}/charts/cluster-issuer/templates/clusterissuer.yaml"), "kind: ClusterIssuer")
    error_message = "cluster-issuer subchart template must define a ClusterIssuer resource"
  }

  assert {
    condition     = strcontains(file("${path.module}/charts/cluster-issuer/templates/clusterissuer.yaml"), "class: traefik")
    error_message = "HTTP-01 solver ingress class must be traefik"
  }
}

run "output_cluster_issuer_name_default" {
  command = plan

  assert {
    condition     = output.cluster_issuer_name == "letsencrypt-prod"
    error_message = "output.cluster_issuer_name must expose default issuer name"
  }
}

run "custom_issuer_name_propagates" {
  command = plan

  variables {
    cluster_issuer_name = "letsencrypt-staging"
  }

  assert {
    condition     = output.cluster_issuer_name == "letsencrypt-staging"
    error_message = "output.cluster_issuer_name must reflect custom input"
  }

  assert {
    condition     = strcontains(helm_release.cluster_issuer.values[0], "\"name\": \"letsencrypt-staging\"")
    error_message = "manifest metadata.name must reflect custom issuer name"
  }
}

run "email_is_required" {
  command = plan
  variables {
    email       = ""
    acme_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
  }
  expect_failures = [var.email]
}

run "reserved_tld_with_prod_acme_fails" {
  command = plan
  variables {
    email                         = "ops@example.net"
    acme_server                   = "https://acme-v02.api.letsencrypt.org/directory"
    allow_reserved_contact_domain = false
  }
  expect_failures = [terraform_data.contact_email_guard]
}
