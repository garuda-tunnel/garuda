locals {
  # Reserved email suffixes — RFC 2606 reserved domains and TLDs that
  # Let's Encrypt's ACME service rejects for account contacts.
  # Convention:
  #   - "@<domain>" entries match emails whose domain is exactly <domain>
  #     (the @ anchors to the local-part boundary).
  #   - ".<tld>" entries match emails whose domain ends in <tld> (any label).
  reserved_email_suffixes = [
    "@example.com",
    "@example.net",
    "@example.org",
    "@example.edu",
    ".invalid",
    ".test",
    ".local",
    "@localhost",
  ]

  email_lower         = lower(var.email)
  email_uses_reserved = anytrue([
    for s in local.reserved_email_suffixes :
    endswith(local.email_lower, s)
  ])
  acme_server_is_staging = strcontains(lower(var.acme_server), "acme-staging")

  contact_email_ok = (
    !local.email_uses_reserved
    || var.allow_reserved_contact_domain
    || local.acme_server_is_staging
  )
}

resource "terraform_data" "contact_email_guard" {
  lifecycle {
    precondition {
      condition     = local.contact_email_ok
      error_message = <<-MSG
        cert_manager: contact email "${var.email}" uses an RFC 2606
        reserved suffix (one of ${jsonencode(local.reserved_email_suffixes)})
        with a non-staging ACME server (${var.acme_server}) and
        allow_reserved_contact_domain=false.

        Let's Encrypt production rejects ACME account registration on
        these domains. Either:
          - supply a real operational email via your stand's SOPS,
          - point acme_server at the staging endpoint
            (https://acme-staging-v02.api.letsencrypt.org/directory),
          - or set allow_reserved_contact_domain = true (only for
            fixtures and the public example).
      MSG
    }
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version

  values = [
    yamlencode({
      installCRDs = true
      # Enable cert-manager's Gateway API integration (gateway-shim controller).
      # Since cert-manager v1.15 the feature is no longer behind the old
      # ExperimentalGatewayAPISupport feature-gate (which became a no-op).
      # The canonical v1.15+ mechanism is config.enableGatewayAPI=true, which
      # starts the gateway-shim controller that watches Gateway resources and
      # auto-creates Certificate objects for TLS listeners. Without this the
      # gateway-shim controller is skipped at startup and cert-manager never
      # creates the hub-tls Secret — the Gateway reports InvalidCertificateRef
      # indefinitely.
      config = {
        enableGatewayAPI = true
      }
    })
  ]
}

resource "helm_release" "cluster_issuer" {
  name             = var.cluster_issuer_name
  namespace        = "cert-manager"
  create_namespace = false
  chart            = "${path.module}/charts/cluster-issuer"

  values = [
    yamlencode({
      name       = var.cluster_issuer_name
      acmeServer = var.acme_server
      email      = var.email
    })
  ]

  depends_on = [helm_release.cert_manager]
}
