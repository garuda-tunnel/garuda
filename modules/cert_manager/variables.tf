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
  type    = bool
  default = false
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
