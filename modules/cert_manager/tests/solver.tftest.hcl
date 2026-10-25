mock_provider "helm" {}

variables {
  email                         = "ops@example.net"
  acme_server                   = "https://acme-staging-v02.api.letsencrypt.org/directory"
  allow_reserved_contact_domain = true
}

run "http01_default_is_unchanged" {
  command = plan

  # The default render must stay byte-identical for cloud stands: the issuer
  # values carry only the three legacy keys and no solver/CA/extraArgs keys.
  assert {
    condition     = helm_release.cluster_issuer.values[0] == yamlencode({ name = "letsencrypt-prod", acmeServer = var.acme_server, email = var.email })
    error_message = "default cluster-issuer values must be the legacy three keys only"
  }

  assert {
    condition     = !strcontains(helm_release.cert_manager.values[0], "extraArgs")
    error_message = "default cert-manager values must not carry extraArgs"
  }

  assert {
    condition     = strcontains(file("${path.module}/charts/cluster-issuer/templates/clusterissuer.yaml"), "class: traefik")
    error_message = "http01 solver must keep the traefik ingress class"
  }
}

run "rfc2136_renders_solver_values" {
  command = plan

  variables {
    solver = "rfc2136"
    rfc2136 = {
      nameserver    = "192.0.2.53:53"
      tsig_key_name = "acme."
      tsig_secret   = "c2VjcmV0"
    }
    acme_ca_bundle = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"
    extra_args     = ["--dns01-recursive-nameservers=192.0.2.53:53", "--dns01-recursive-nameservers-only"]
  }

  assert {
    condition     = strcontains(helm_release.cluster_issuer.values[0], "\"nameserver\": \"192.0.2.53:53\"")
    error_message = "rfc2136 nameserver must reach the issuer values"
  }

  assert {
    condition     = strcontains(helm_release.cluster_issuer.values[0], "\"tsigKeyName\": \"acme.\"")
    error_message = "tsig key name must reach the issuer values"
  }

  assert {
    condition     = strcontains(helm_release.cluster_issuer.values[0], "\"tsigAlgorithm\": \"HMACSHA256\"")
    error_message = "tsig algorithm must default to HMACSHA256"
  }

  assert {
    condition     = strcontains(helm_release.cluster_issuer.values[0], "\"caBundle\": \"${base64encode(var.acme_ca_bundle)}\"")
    error_message = "caBundle must be the base64 of the supplied PEM"
  }

  assert {
    condition     = !strcontains(helm_release.cluster_issuer.values[0], "c2VjcmV0")
    error_message = "tsig secret must not appear in plain issuer values"
  }

  assert {
    condition     = length(helm_release.cluster_issuer.set_sensitive) == 1
    error_message = "tsig secret must be passed through set_sensitive"
  }

  assert {
    condition     = strcontains(helm_release.cert_manager.values[0], "--dns01-recursive-nameservers-only")
    error_message = "extra_args must reach the cert-manager extraArgs value"
  }

  # The rendered ClusterIssuer solver block lives in the chart templates.
  assert {
    condition = alltrue([
      for k in ["rfc2136:", "nameserver:", "tsigKeyName:", "tsigAlgorithm:", "tsigSecretSecretRef:", "caBundle:"] :
      strcontains(file("${path.module}/charts/cluster-issuer/templates/clusterissuer.yaml"), k)
    ])
    error_message = "clusterissuer template must render the rfc2136 solver fields and caBundle"
  }

  assert {
    condition     = strcontains(file("${path.module}/charts/cluster-issuer/templates/tsig-secret.yaml"), "kind: Secret")
    error_message = "chart must ship the TSIG Secret template"
  }
}

run "rfc2136_requires_settings" {
  command = plan

  variables {
    solver = "rfc2136"
  }

  expect_failures = [var.rfc2136]
}

run "unknown_solver_rejected" {
  command = plan

  variables {
    solver = "dns01"
  }

  expect_failures = [var.solver]
}
