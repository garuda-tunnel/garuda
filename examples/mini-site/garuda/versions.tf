terraform {
  required_version = ">= 1.10.0"

  # The >= 1.10 floor matches the OpenTofu release line tested across the
  # rest of the mini-site (matching the k3s_cloud_init, garuda_k8s, and
  # wireguard/kube modules). Earlier 1.x releases are not exercised in CI;
  # bumping this floor again should be coordinated with those modules.

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.3"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = ">= 1.86.0"
    }
    wireguard = {
      source  = "OJFord/wireguard"
      version = ">= 0.4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30.0"
    }
  }
}
