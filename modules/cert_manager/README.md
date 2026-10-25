# cert_manager

Installs cert-manager on the hub Kubernetes cluster and creates one
`ClusterIssuer` for Let's Encrypt using HTTP-01 challenge solved by
Traefik ingress. An optional RFC 2136 (TSIG) DNS-01 solver is available for
stands with a private zone.

## Inputs

| Variable | Type | Default | Description |
|---|---|---|---|
| `email` | string | (required) | Contact email for ACME account and expiry notices. The module enforces a runtime guard: if the domain part is an IANA reserved/example domain (e.g. `example.net`), you must also set `allow_reserved_contact_domain = true`; without that flag the ClusterIssuer creation is blocked. Use a real operational address in production; pass a staging ACME server URL and set the allow flag for fixtures and test stands. |
| `acme_server` | string | Let's Encrypt production URL | ACME directory URL. Override with the Let's Encrypt staging URL (`https://acme-staging-v02.api.letsencrypt.org/directory`) for test stands and CI to avoid rate-limit exhaustion. |
| `allow_reserved_contact_domain` | bool | `false` | Set to `true` to permit reserved or example domains (e.g. `example.net`) in the `email` argument. Required when the stand uses a placeholder address; has no effect on production email addresses. |
| `cluster_issuer_name` | string | `letsencrypt-prod` | ClusterIssuer resource name. |
| `chart_version` | string | module default | Jetstack cert-manager Helm chart version. |
| `solver` | string | `http01` | `http01` (traefik ingress) or `rfc2136` (DNS-01 with TSIG). The default renders the same issuer as before. |
| `rfc2136` | object (sensitive) | `null` | `{ nameserver, tsig_key_name, tsig_algorithm = "HMACSHA256", tsig_secret }`; required when `solver = "rfc2136"`. The secret goes into a Secret in the `cert-manager` namespace via a sensitive Helm value. |
| `acme_ca_bundle` | string | `null` | PEM CA bundle for the ACME server TLS certificate; base64-encoded into `spec.acme.caBundle`. |
| `extra_args` | list(string) | `[]` | Extra cert-manager controller arguments (Helm `extraArgs`), e.g. `--dns01-recursive-nameservers-only`. |

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
- Does not provision the DNS server or TSIG key used by the `rfc2136` solver, and has no cloud DNS API integration.
