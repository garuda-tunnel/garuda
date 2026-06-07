# cert_manager

Installs cert-manager on the hub Kubernetes cluster and creates one
`ClusterIssuer` for Let's Encrypt using HTTP-01 challenge solved by
Traefik ingress.

## Inputs

| Variable | Type | Default | Description |
|---|---|---|---|
| `email` | string | (required) | Contact email for ACME account and expiry notices. The module enforces a runtime guard: if the domain part is an IANA reserved/example domain (e.g. `example.net`), you must also set `allow_reserved_contact_domain = true`; without that flag the ClusterIssuer creation is blocked. Use a real operational address in production; pass a staging ACME server URL and set the allow flag for fixtures and test stands. |
| `acme_server` | string | Let's Encrypt production URL | ACME directory URL. Override with the Let's Encrypt staging URL (`https://acme-staging-v02.api.letsencrypt.org/directory`) for test stands and CI to avoid rate-limit exhaustion. |
| `allow_reserved_contact_domain` | bool | `false` | Set to `true` to permit reserved or example domains (e.g. `example.net`) in the `email` argument. Required when the stand uses a placeholder address; has no effect on production email addresses. |
| `cluster_issuer_name` | string | `letsencrypt-prod` | ClusterIssuer resource name. |
| `chart_version` | string | module default | Jetstack cert-manager Helm chart version. |

## Outputs

| Output | Description |
|---|---|
| `cluster_issuer_name` | Name of created `ClusterIssuer`. |

## Providers

```hcl
module "cert_manager" {
  source = "../../../modules/cert_manager"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  # ops@example.net is a documented placeholder valid only for test fixtures.
  # example.net is an IANA reserved domain, so the staging ACME server and
  # allow_reserved_contact_domain=true are required to keep the stand apply-able.
  # Production stands must supply a real operational address and omit these two
  # overrides (or point acme_server at the production Let's Encrypt endpoint).
  email                         = "ops@example.net"
  acme_server                   = "https://acme-staging-v02.api.letsencrypt.org/directory"
  allow_reserved_contact_domain = true
}
```

## What this module does NOT do

- Does not create per-app `Certificate` resources.
- Does not install or configure Traefik itself.
- Does not perform DNS-01 setup or cloud DNS API integration.
