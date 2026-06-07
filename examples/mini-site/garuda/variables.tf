# --- environment ---
variable "env_slug" {
  description = "Short identifier for this environment (e.g. mini-site). Used as a prefix in resource names."
  type        = string
}

# --- Hub SSH connection bundle from infra/ (single object) ---
variable "connection_data_hub" {
  description = "SSH connection bundle for the hub host."
  sensitive   = true
  type = object({
    host                 = string
    user                 = string
    connection           = string
    network_os           = string
    password             = optional(string)
    ssh_private_key_file = optional(string)
    ssh_private_key      = optional(string)
    instance_token       = string
  })
}

# --- Edge SSH connection bundles from infra/ (map keyed by edge slug) ---
variable "connection_data_edges" {
  description = "Per-edge SSH connection bundles (keyed by edge slug)."
  sensitive   = true
  type = map(object({
    host                 = string
    user                 = string
    connection           = string
    network_os           = string
    password             = optional(string)
    ssh_private_key_file = optional(string)
    ssh_private_key      = optional(string)
    instance_token       = string
  }))
}

# --- Cloudflare record for the hub host (used as WG endpoint host) ---
variable "cloudflare_hub" {
  description = "Cloudflare record facts for hub (FQDN used as WireGuard endpoint)."
  type = object({
    zone_id     = string
    record_name = string
  })
}

# --- Cloudflare records for edges (keyed by edge slug) ---
variable "cloudflare_edges" {
  description = "Cloudflare record facts for edge hosts (keyed by edge slug)."
  type = map(object({
    zone_id     = string
    record_name = string
  }))
}

# --- RouterOS handles (same shape as inputs.tfvars.yaml::routeros) ---
variable "routeros" {
  description = "RouterOS connection handles from infra/."
  type = object({
    hostname         = string
    management_host  = string
    user             = string
    uplink_interface = string
  })
}

# --- RouterOS password (from SOPS via root.hcl, not from infra dependency) ---
variable "routeros_password" {
  type      = string
  sensitive = true
}

# --- Topology CIDRs (flat, non host-scoped) ---
variable "backbone_subnet" { type = string }
variable "border_subnet" { type = string }
variable "firezone_client_subnet" { type = string }

# --- Hub FQDN prefix + base domain (derives Firezone server_url) ---
variable "hub_fqdn_prefix" {
  description = "FQDN prefix for the hub host (prepended to base_domain)."
  type        = string
}

variable "base_domain" {
  description = "Base DNS domain for this topology (e.g. example.net)."
  type        = string
}

# --- Edges map (mirrors infra var.edges; consumed by garuda for WG config) ---
variable "edges" {
  description = "Map of edge hosts with WireGuard tunnel parameters."
  type = map(object({
    machine_type        = string
    boot_disk_gb        = number
    region              = string
    zone                = string
    fqdn_prefix         = string
    hub_cidr            = string
    peer_cidr           = string
    listen_port         = number
    ospf_router_id_hub  = string
    ospf_router_id_peer = string
  }))
  default = {}
}

# --- Hub-ros WireGuard tunnel (RouterOS ↔ hub) ---
variable "hub_ros" {
  description = "WireGuard tunnel parameters for the RouterOS ↔ hub tunnel."
  type = object({
    hub_cidr           = string
    routeros_cidr      = string
    listen_port        = number
    ospf_router_id_hub = string
  })
}

# --- OSPF router ids for non-tunnel workloads ---
variable "ospf_router_ids" {
  type = object({
    firezone   = string
    ipt_server = string
  })
}

# --- Local border egress (border_router) ---
variable "border_router" {
  description = <<EOT
border_router OSPF router-id. The same IPv4 is materialised as the dummy0 /32 on
the border_router pod and advertised via OSPF, so it is the gw=<router_id>
next-hop ipt_server targets for RU/local egress (loopback-as-router-id). It must
be (a) a /32 outside backbone_subnet and border_subnet, and (b) distinct from
every other OSPF router-id in ospf_router_ids.* and the edges' router-ids.
EOT
  type = object({
    router_id = string
  })

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.border_router.router_id))
    error_message = "border_router.router_id must be an IPv4 address."
  }
}

variable "border_router_image" {
  description = "egress-setup image for border_router. Overridden at the stand (test-config) to pin a locally-built/imported tag, mirroring var.frr_sidecar_image / var.ipt_powerdns_image."
  type        = string
  default     = "ghcr.io/garuda-tunnel/garuda-border-router:latest"
}

# --- Geo routing ---
variable "ipt_routes_germany_nets" { type = list(string) }

# --- Firezone (SOPS secrets + public OIDC client id) ---
variable "firezone_admin_password" {
  type      = string
  sensitive = true
}
variable "firezone_admin_email" {
  description = "Initial Firezone admin email used by the firezone module."
  type        = string
  default     = "fz-admin@example.net"
}

variable "cert_manager_email" {
  description = <<-EOT
    Contact email for cert-manager's Let's Encrypt ClusterIssuer.
    Decoupled from firezone_admin_email (which is a user identity,
    not an ACME ops contact). Stands SHOULD override this via SOPS
    with a real operational address. The default below is a
    documented placeholder; the cert_manager module is invoked with
    allow_reserved_contact_domain=true and staging ACME so the
    placeholder remains apply-able for examples and tests.
  EOT
  type    = string
  default = "ops@example.net"
}

variable "cert_manager_acme_server" {
  description = <<-EOT
    ACME directory URL for cert-manager's ClusterIssuer. Default is
    Let's Encrypt staging so the public mini-site example remains
    apply-able with a placeholder email. Real stands override to the
    LE production endpoint
    `https://acme-v02.api.letsencrypt.org/directory` via
    inputs.tfvars.yaml or SOPS.
  EOT
  type    = string
  default = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

variable "cert_manager_allow_reserved_contact_domain" {
  description = <<-EOT
    Suppress the cert_manager runtime guard that rejects ACME contact
    emails on RFC 2606 reserved TLDs. Default true matches the
    placeholder email + staging ACME pair used by the public example
    and module tests. Real stands MUST set this false in tandem with
    a real email + production ACME so any placeholder leak fails fast
    at apply.
  EOT
  type    = bool
  default = true
}

variable "firezone_oidc_google_client_id" { type = string }
variable "firezone_oidc_google_client_secret" {
  type      = string
  sensitive = true
}

variable "firezone_encryption_secrets" {
  description = <<-EOT
Forwarded to module.firezone_kube.encryption_secrets. See the module
documentation for the recovery procedure. Default {} means random
generation on first apply; operators supplying this object via
secrets.sops.yaml restore a database encrypted under prior keys.
EOT
  type = object({
    guardianSecretKey     = optional(string)
    secretKeyBase         = optional(string)
    liveViewSigningSalt   = optional(string)
    cookieSigningSalt     = optional(string)
    cookieEncryptionSalt  = optional(string)
    databaseEncryptionKey = optional(string)
    databasePassword      = optional(string)
  })
  default   = {}
  sensitive = true
}

# --- Smoke client (pre-existing VPN client, not managed infra) ---
variable "smoke_client_firezone" {
  type = object({
    inventory_name  = string
    management_host = string
    user            = string
  })
}

# --- RouterOS LAN gateway (used for WG handshake bypass route) ---
variable "routeros_lan_gateway" {
  description = "Default gateway on the RouterOS LAN (used as nexthop for the WG handshake bypass route)."
  type        = string
}

# --- Workload container images ---
variable "wireguard_image" {
  description = "Docker image for the WireGuard container workload."
  type        = string
  default     = "ghcr.io/garuda-tunnel/garuda-wireguard:latest"
}

variable "frr_sidecar_image" {
  description = "Docker image for the FRR sidecar container used by Kubernetes WireGuard workloads."
  type        = string
  default     = "ghcr.io/garuda-tunnel/garuda-frr-sidecar:latest"
}

variable "fz_firezone_image" {
  description = "Docker image for the Firezone container workload."
  type        = string
  default     = "ghcr.io/garuda-tunnel/garuda-firezone:latest"
}

variable "ipt_server_image" {
  description = "Docker image for the ipt_server container workload."
  type        = string
  default     = "ghcr.io/garuda-tunnel/garuda-ipt-server:latest"
}

variable "ipt_powerdns_image" {
  description = "Docker image for the PowerDNS container used by ipt_server."
  type        = string
  default     = "ghcr.io/garuda-tunnel/garuda-powerdns:latest"
}

# --- Path to garuda-tunnel state JSON ---
variable "tunnel_path" {
  description = <<EOT
Absolute filesystem path to the JSON file written by the Terragrunt
`tunnel_up_script` running `uvx ... garuda-tunnel start`. The JSON is an
`OutputSchema` document; the consumer reads only
`connections[<node>].kube_targets.k3s.path` (the absolute path to the
patched kubeconfig that garuda-tunnel materializes under its session
dir when `daemon.materialize=true`).

Leave empty during init / `tofu test` runs that do not need a live
tunnel state; in that mode `locals.tf` decodes a synthetic empty
structure so provider blocks evaluate inertly (see providers.tf
inert branch).

Shape reference: https://github.com/garuda-tunnel/garuda-tunnel README,
"Output reference" + spec
docs/superpowers/specs/2026-05-30-garuda-tunnel-kube-targets-migration-design.md.
EOT
  type        = string
  default     = ""
}
