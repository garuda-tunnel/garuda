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

# --- Stand opt-out flags (defaults reproduce the cloud/vpn2 plan) ---
variable "routeros_enabled" {
  description = "Manage the RouterOS peer (hub-ros tunnel, RouterOS NAT/route). Set false for stands without RouterOS; the RouterOS inputs may then be null."
  type        = bool
  default     = true
}

variable "remnawave_enabled" {
  description = "Deploy the Remnawave panel and node (and expose their gateway hostnames). Set false for stands without Remnawave."
  type        = bool
  default     = true
}

variable "firezone_oidc_enabled" {
  description = "Configure the Google OIDC provider on Firezone. Set false to use local Firezone credentials only; the OIDC client id/secret may then be null."
  type        = bool
  default     = true
}

# --- RouterOS handles (same shape as inputs.tfvars.yaml::routeros) ---
variable "routeros" {
  description = "RouterOS connection handles from infra/. Required when routeros_enabled."
  type = object({
    hostname         = string
    management_host  = string
    user             = string
    uplink_interface = string
  })
  default  = null
  nullable = true

  validation {
    condition     = !var.routeros_enabled || var.routeros != null
    error_message = "routeros must be set when routeros_enabled is true."
  }
}

# --- RouterOS password (from SOPS via root.hcl, not from infra dependency) ---
variable "routeros_password" {
  description = "RouterOS API password. Required when routeros_enabled."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true

  validation {
    condition     = !var.routeros_enabled || var.routeros_password != null
    error_message = "routeros_password must be set when routeros_enabled is true."
  }
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
  description = "WireGuard tunnel parameters for the RouterOS ↔ hub tunnel. Required when routeros_enabled."
  type = object({
    hub_cidr           = string
    routeros_cidr      = string
    listen_port        = number
    ospf_router_id_hub = string
  })
  default  = null
  nullable = true

  validation {
    condition     = !var.routeros_enabled || var.hub_ros != null
    error_message = "hub_ros must be set when routeros_enabled is true."
  }
}

# --- OSPF router ids for non-tunnel workloads ---
variable "ospf_router_ids" {
  description = "OSPF router ids. remnawave_node is required only when remnawave_enabled."
  type = object({
    firezone       = string
    ipt_server     = string
    remnawave_node = optional(string)
  })

  validation {
    condition     = !var.remnawave_enabled || var.ospf_router_ids.remnawave_node != null
    error_message = "ospf_router_ids.remnawave_node must be set when remnawave_enabled is true."
  }
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
  description = "egress-setup image for border_router. Overridden at the stand (test-config) to pin a locally-built/imported tag, mirroring var.ipt_powerdns_image."
  type        = string
  default     = ""
}

# --- Geo routing ---
variable "ipt_routes_germany_nets" { type = list(string) }

variable "ipt_route_groups" {
  description = <<EOT
Optional override of the ipt_server route groups. Each group lists the
destination rules and the ordered egress roles (primary first, then
fallbacks). A role is an edge key from var.edges or "border" (the local
border_router). Null keeps the built-in country/domain routing.
EOT
  type = list(object({
    egress = list(string)
    rules  = list(string)
  }))
  default = null

  validation {
    condition = var.ipt_route_groups == null || (
      length(var.ipt_route_groups) > 0 && alltrue([
        for g in var.ipt_route_groups : length(g.egress) > 0 && alltrue([
          for r in g.egress : contains(concat(keys(var.edges), ["border"]), r)
        ])
      ])
    )
    error_message = "ipt_route_groups must contain groups with egress entries that are edge keys from var.edges or \"border\"."
  }
}

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
  type        = string
  default     = "ops@example.net"
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
  type        = string
  default     = "https://acme-staging-v02.api.letsencrypt.org/directory"
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
  type        = bool
  default     = true
}

variable "firezone_oidc_google_client_id" {
  description = "Google OIDC client id. Required when firezone_oidc_enabled."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = !var.firezone_oidc_enabled || var.firezone_oidc_google_client_id != null
    error_message = "firezone_oidc_google_client_id must be set when firezone_oidc_enabled is true."
  }
}

variable "firezone_oidc_google_client_secret" {
  description = "Google OIDC client secret. Required when firezone_oidc_enabled."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true

  validation {
    condition     = !var.firezone_oidc_enabled || var.firezone_oidc_google_client_secret != null
    error_message = "firezone_oidc_google_client_secret must be set when firezone_oidc_enabled is true."
  }
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

# --- RouterOS LAN gateway (used for WG handshake bypass route) ---
variable "routeros_lan_gateway" {
  description = "Default gateway on the RouterOS LAN (used as nexthop for the WG handshake bypass route). Required when routeros_enabled."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = !var.routeros_enabled || var.routeros_lan_gateway != null
    error_message = "routeros_lan_gateway must be set when routeros_enabled is true."
  }
}

# --- pod-reaper (hub and edges) ---
variable "pod_reaper_max_unready" {
  description = "Override of the garuda chart's podReaper.maxUnready on every cluster, for example \"600s\". Image pulls count as unready time: a stand with a slow first pull needs more than the chart default (120s). Null keeps the chart default."
  type        = string
  default     = null
}

# --- Host LANs behind the nodes ---
variable "host_lans" {
  description = <<-EOT
    RFC 1918 LANs that live on a node host (not in the cluster) and must be reachable through garuda, keyed by
    node: "hub" or an edge key. The pod that owns the node's border interface (border-router on the hub,
    wg-<edge> on an edge) gets a static route to the LAN via the border gateway (the node), redistributes it
    into OSPF, and holds host_lan_alias on border. The node needs a return route for firezone_client_subnet via
    that alias, see examples/local-stand. The client subnet must be private (RFC 1918): the wireguard pods only
    bypass the border default for private destinations. Empty (default) changes nothing.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, c in var.host_lans : can(cidrnetmask(c)) && anytrue([
        for r in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] : try(cidrcontains(r, c), false)
      ])
    ])
    error_message = "host_lans values must be IPv4 CIDRs contained in 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16."
  }
  validation {
    condition     = alltrue([for k in keys(var.host_lans) : k == "hub" || contains(keys(var.edges), k)])
    error_message = "host_lans keys must be \"hub\" or a key of var.edges."
  }
  validation {
    condition = alltrue(flatten([
      for k, c in var.host_lans : [
        for o in [var.firezone_client_subnet, var.backbone_subnet, var.border_subnet] :
        !try(cidrcontains(o, c) || cidrcontains(c, o), false)
      ]
    ]))
    error_message = "host_lans must not overlap firezone_client_subnet, backbone_subnet or border_subnet."
  }
  validation {
    condition = length(var.host_lans) == 0 || anytrue([
      for r in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] : try(cidrcontains(r, var.firezone_client_subnet), false)
    ])
    error_message = "host_lans needs an RFC 1918 firezone_client_subnet: replies to clients and LAN-initiated flows are only kept inside for private destinations."
  }
}

variable "host_lan_alias" {
  description = "Fixed address of the pod that owns a node's border interface (see host_lans), the next hop of the node's return route for the Firezone client subnet. It lives OUTSIDE border_subnet on purpose, so the border bridge's host-local IPAM can never hand it to another pod. Link-local by default."
  type        = string
  default     = "169.254.1.1"

  validation {
    # cidrnetmask, not cidrhost: the latter also accepts IPv6 literals.
    condition     = can(cidrnetmask("${var.host_lan_alias}/32"))
    error_message = "host_lan_alias must be an IPv4 address."
  }
  validation {
    condition = !anytrue([
      for o in [var.border_subnet, var.backbone_subnet, var.firezone_client_subnet] : try(cidrcontains(o, var.host_lan_alias), false)
    ])
    error_message = "host_lan_alias must be outside border_subnet, backbone_subnet and firezone_client_subnet."
  }
}

# --- cert-manager solver (hub) ---
variable "cert_manager_solver" {
  description = "ACME solver: \"http01\" (default, traefik) or \"rfc2136\" (DNS-01 with TSIG)."
  type        = string
  default     = "http01"
}

variable "cert_manager_rfc2136" {
  description = "RFC 2136 solver settings (nameserver host:port, TSIG key name/algorithm/secret). Required when cert_manager_solver is \"rfc2136\"."
  type = object({
    nameserver     = string
    tsig_key_name  = string
    tsig_algorithm = optional(string, "HMACSHA256")
    tsig_secret    = string
  })
  default   = null
  sensitive = true
}

variable "cert_manager_acme_ca_bundle" {
  description = "Optional PEM CA bundle for the ACME server TLS certificate (base64-encoded by the module into spec.acme.caBundle)."
  type        = string
  default     = null
}

variable "cert_manager_extra_args" {
  description = "Extra cert-manager controller arguments (Helm extraArgs), for example DNS-01 recursive nameserver flags."
  type        = list(string)
  default     = []
}

# --- Workload container images ---
variable "wireguard_image" {
  description = "Docker image for the WireGuard container workload. Leave empty (default) to let the chart pin its own image at :.Chart.Version; set to override (never :latest)."
  type        = string
  default     = ""
}

variable "fz_firezone_image" {
  description = "Docker image for the Firezone container workload. Leave empty (default) to let the chart pin its own image at :.Chart.Version; set to override (never :latest)."
  type        = string
  default     = ""
}

variable "ipt_server_image" {
  description = "Docker image for the ipt_server container workload. Leave empty (default) to let the chart pin its own image at :.Chart.Version; set to override (never :latest)."
  type        = string
  default     = ""
}

variable "ipt_powerdns_image" {
  description = "Docker image for the PowerDNS container used by ipt_server. Leave empty (default) to let the chart pin its image at :.Chart.Version; set to override (never :latest)."
  type        = string
  default     = ""
}

variable "ipt_powerdns_extra_config" {
  description = "Raw PowerDNS Recursor YAML settings for the ipt-server workload Recursor (e.g. forward_zones_recurse / dnssec.negative_trustanchors). Empty (default) adds nothing."
  type        = string
  default     = ""
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
