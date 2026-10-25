# --- environment ---
variable "env_slug" {
  description = "Short identifier for this environment (e.g. mini-site). Used as a prefix in resource names."
  type        = string
}

# --- Proxmox VE (hub and client VMs) ---
variable "proxmox" {
  description = <<EOT
Proxmox VE node, pool, storage, network and per-VM sizing for the hub and
client VMs. The provider API token is never a variable: it comes from the
PROXMOX_VE_API_TOKEN environment variable.
EOT
  type = object({
    endpoint      = string
    node_name     = string
    pool_id       = string
    datastore_id  = string
    bridge        = string
    image_file_id = string
    gateway       = string
    dns_servers   = list(string)
    hub = object({
      address   = string
      cores     = number
      memory_mb = number
      disk_gb   = number
    })
    client = object({
      address   = string
      cores     = number
      memory_mb = number
      disk_gb   = number
    })
  })

  validation {
    condition     = can(cidrnetmask("${var.proxmox.gateway}/32"))
    error_message = "proxmox.gateway must be an IPv4 address."
  }

  validation {
    condition     = can(cidrnetmask("${var.proxmox.hub.address}/32")) && can(cidrnetmask("${var.proxmox.client.address}/32"))
    error_message = "proxmox.hub.address and proxmox.client.address must be IPv4 addresses."
  }

  validation {
    condition     = length(var.proxmox.dns_servers) > 0
    error_message = "proxmox.dns_servers must not be empty (cloud-init static IP config needs explicit resolvers)."
  }
}

# --- GCP (public handle) ---
variable "gcp" {
  description = "Google Cloud project handle. Per-VM region/zone live on host objects."
  type = object({
    project_id = string
  })
}

variable "gcp_image" {
  description = "Boot image (family or full path) for the GCP edge VMs. Default is Ubuntu 26.04 LTS: k3s-bootstrap v0.2.0 preflight asserts 26.04, while the gcp_compute_host default is 24.04."
  type        = string
  default     = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2604-lts-amd64"

  validation {
    condition     = trimspace(var.gcp_image) != ""
    error_message = "gcp_image must not be blank."
  }
}

# --- GCP service-account credentials (SOPS secret) ---
variable "gcp_credentials_json" {
  type      = string
  sensitive = true
}

# --- Cloudflare (public handle) ---
variable "cloudflare" {
  description = "Cloudflare zone handle."
  type = object({
    zone_name = string
  })
}

# --- Cloudflare API token (SOPS secret) ---
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

# --- RouterOS connection (pre-existing physical device) ---
variable "routeros_enabled" {
  description = "Manage the RouterOS bootstrap resources. Set false for stands without RouterOS; the routeros inputs may then be null."
  type        = bool
  default     = true
}

variable "routeros" {
  description = "RouterOS connection handles used for infra bootstrap and provider setup. Required when routeros_enabled."
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

# --- RouterOS password (SOPS secret) ---
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

# --- Stand SSH key (path only; the private key never enters state) ---
variable "ssh_public_key_file" {
  description = "Path to the stand SSH public key. Seeded on every VM (Proxmox cloud-init user_account, GCP metadata, k3s-bootstrap authorized_keys)."
  type        = string

  validation {
    condition     = trimspace(var.ssh_public_key_file) != ""
    error_message = "ssh_public_key_file must not be blank."
  }
}

variable "ssh_private_key_file" {
  description = "Path to the stand SSH private key matching ssh_public_key_file. Referenced by path only; this root never reads its content."
  type        = string

  validation {
    condition     = trimspace(var.ssh_private_key_file) != ""
    error_message = "ssh_private_key_file must not be blank."
  }
}

variable "known_hosts_file" {
  description = <<EOT
Absolute path to the stand known_hosts file, appended by the ssh-keyscan
step after each VM is created (trust-on-first-use). Must be absolute (a
leading ~ is expanded) because it is also consumed outside this module:
export ANSIBLE_SSH_ARGS="-o UserKnownHostsFile=<this path>" so that
k3s-bootstrap's StrictHostKeyChecking=yes verifies against the scanned
keys — see the README.

The keyscan reruns only when a host or its generation changes — not when
this path moves. Keep the path stable; if you move it, repopulate the new
file by replacing the scan resources explicitly, e.g.
terragrunt apply -replace='terraform_data.known_hosts["hub"]' (client and
each edge slug likewise).
EOT
  type        = string

  validation {
    condition     = trimspace(var.known_hosts_file) != ""
    error_message = "known_hosts_file must not be blank."
  }

  validation {
    condition     = can(regex("^/", pathexpand(var.known_hosts_file)))
    error_message = "known_hosts_file must resolve to an absolute path (~/... is expanded; bare relative paths are rejected)."
  }
}

# --- k3s (installed by k3s-bootstrap, not cloud-init) ---
variable "k3s_version" {
  description = "Exact k3s version pin passed to every k3s-bootstrap node."
  type        = string

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+\\+k3s\\d+$", var.k3s_version))
    error_message = "k3s_version must be an exact pin matching ^v\\d+\\.\\d+\\.\\d+\\+k3s\\d+$, for example v1.33.0+k3s1."
  }
}

variable "cluster_cidrs" {
  description = "Pod and service network CIDRs of the per-node k3s clusters (k3s defaults 10.42.0.0/16 and 10.43.0.0/16); the only cluster networks the managed firewall trusts."
  type        = list(string)

  validation {
    condition     = length(var.cluster_cidrs) > 0 && alltrue([for cidr in var.cluster_cidrs : can(cidrhost(cidr, 0))])
    error_message = "cluster_cidrs must be a non-empty list of valid CIDRs."
  }
}

variable "api_trusted_cidrs" {
  description = "CIDRs allowed to reach the k3s API on every node (for example the stand's backbone and border subnets)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.api_trusted_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every api_trusted_cidrs entry must be a valid CIDR."
  }
}

# --- Edges map (GCP-managed, keyed by slug: pt, de, …) ---
variable "edges" {
  description = "Map of GCP edge hosts. Each entry provides compute sizing and WireGuard tunnel parameters."
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

  validation {
    condition     = !contains(keys(var.edges), "hub") && !contains(keys(var.edges), "client")
    error_message = "The edge slugs \"hub\" and \"client\" are reserved by the Proxmox hub/client: k3s.tf merges them after the edges map, so these keys would silently replace the Proxmox entries. Use different slugs."
  }
}

# --- Operator SSH keys appended to every managed VM ---
variable "operator_ssh_keys" {
  type        = list(string)
  description = <<EOT
Operator/extra SSH keys passed verbatim into metadata['ssh-keys'] on every
managed GCP VM. Each entry MUST be in `username:keytype keydata [comment]`
format (e.g. `operator:ssh-ed25519 AAAA... operator@workstation`). The cloud guest
agent on the VM creates the user on first contact and writes the key into
that user's ~/.ssh/authorized_keys. See
garuda-repo/modules/gcp_compute_host/README.md for details.
EOT
  default     = []
}

# --- DNS ---
variable "hub_fqdn_prefix" {
  description = "FQDN prefix for the hub host (prepended to base_domain)."
  type        = string
}

variable "base_domain" {
  description = "Base DNS domain for this topology (e.g. example.net). Every Cloudflare record of this unit lives under it."
  type        = string
}
