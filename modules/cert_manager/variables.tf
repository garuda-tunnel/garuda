variable "email" {
  description = <<-EOT
    Required. Contact email for Let's Encrypt ACME account registration
    and expiry notifications. Must be a valid address format. No default —
    callers must supply an explicit value. Fixtures and the public mini-site
    example pass a placeholder (e.g. ops@example.net) together with
    allow_reserved_contact_domain = true and a staging ACME server so the
    runtime reserved-TLD guard does not fire.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.email))
    error_message = "email must be a valid email address."
  }
}

variable "allow_reserved_contact_domain" {
  description = <<-EOT
    When true, suppress the runtime guard that rejects ACME contact
    emails on RFC 2606 reserved TLDs (example.com, .invalid, .test,
    etc.). Intended for fixtures and the public mini-site example
    where the example domain is documented. Production stands MUST
    leave this false so a placeholder leak fails fast.
  EOT
  type        = bool
  default     = false
}

variable "acme_server" {
  description = "ACME directory URL. Override to staging for test environments."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"

  validation {
    condition     = can(regex("^https://", var.acme_server))
    error_message = "acme_server must start with https://"
  }
}

variable "cluster_issuer_name" {
  description = "ClusterIssuer resource name to create."
  type        = string
  default     = "letsencrypt-prod"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.cluster_issuer_name))
    error_message = "cluster_issuer_name must be a valid DNS-1123 label."
  }
}

variable "chart_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "v1.18.2"
}

variable "solver" {
  description = <<-EOT
    ACME challenge solver for the ClusterIssuer. "http01" (default) keeps the
    traefik HTTP-01 solver used by cloud stands; "rfc2136" renders a DNS-01
    solver that updates records over RFC 2136 with a TSIG key (see var.rfc2136).
  EOT
  type        = string
  default     = "http01"

  validation {
    condition     = contains(["http01", "rfc2136"], var.solver)
    error_message = "solver must be \"http01\" or \"rfc2136\"."
  }
}

variable "rfc2136" {
  description = <<-EOT
    RFC 2136 solver settings, required when solver = "rfc2136". nameserver is
    host:port of the authoritative server accepting TSIG-signed updates;
    tsig_secret is the base64 TSIG key material and is stored in a Secret in
    the cert-manager namespace (passed to Helm as a sensitive value).
  EOT
  type = object({
    nameserver     = string
    tsig_key_name  = string
    tsig_algorithm = optional(string, "HMACSHA256")
    tsig_secret    = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.solver != "rfc2136" || var.rfc2136 != null
    error_message = "rfc2136 must be set when solver = \"rfc2136\"."
  }
}

variable "acme_ca_bundle" {
  description = "Optional PEM CA bundle that signs the ACME server TLS certificate. Base64-encoded into the ClusterIssuer spec.acme.caBundle."
  type        = string
  default     = null
}

variable "extra_args" {
  description = "Extra cert-manager controller arguments, passed to the Helm chart as extraArgs (for example --dns01-recursive-nameservers-only)."
  type        = list(string)
  default     = []
}
