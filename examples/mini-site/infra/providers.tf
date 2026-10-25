# The Proxmox API token is never a variable: the provider reads it from the
# PROXMOX_VE_API_TOKEN environment variable.
provider "proxmox" {
  endpoint = var.proxmox.endpoint
}

# Google provider is configured WITHOUT region/zone at the provider level
# because edges live in different regions (pt: us-central1, de: europe-west3).
# Each module call passes region/zone explicitly.
provider "google" {
  credentials = var.gcp_credentials_json
  project     = var.gcp.project_id
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# When routeros_enabled=false every routeros_* resource is count-gated, but
# OpenTofu still configures the provider. A REST placeholder plus an explicit
# version constructs the client without dialing or reading RouterOS inputs.
provider "routeros" {
  hosturl          = var.routeros_enabled ? "api://${var.routeros.management_host}" : "https://127.0.0.1:0"
  routeros_version = var.routeros_enabled ? null : "7.0"
  username         = var.routeros_enabled ? var.routeros.user : "unused"
  password         = var.routeros_enabled ? var.routeros_password : "unused"
  insecure         = true
}
