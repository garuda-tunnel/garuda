terraform {
  # >= 1.9.0: floor imposed by the k3s-bootstrap module (v0.2.0).
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.115"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.40.0, < 5.0.0"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = ">= 1.86.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.3"
    }
  }
}
