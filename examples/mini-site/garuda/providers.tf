provider "routeros" {
  hosturl  = "api://${var.routeros.management_host}"
  username = var.routeros.user
  password = var.routeros_password
  insecure = true
}

# --- Edge k3s providers: one instanced pair over var.edges. ---
#
# Each instance is fed by local.edges_kubeconfig_path[each.key] from the
# garuda-tunnel state file (variant C: garuda-tunnel materializes a fully
# patched kubeconfig per node, so a single config_path is sufficient).
#
# Inert branch: when the path is "" (mock-state, tofu test), config_path is
# null AND host is pinned to an unreachable loopback with empty cert material
# so the providers never fall back to $KUBECONFIG / ~/.kube/config.

provider "helm" {
  alias    = "edge"
  for_each = var.edges

  kubernetes {
    config_path            = local.edges_kubeconfig_path[each.key] != "" ? local.edges_kubeconfig_path[each.key] : null
    host                   = local.edges_kubeconfig_path[each.key] == "" ? "https://127.0.0.1:0" : null
    cluster_ca_certificate = local.edges_kubeconfig_path[each.key] == "" ? "" : null
    client_certificate     = local.edges_kubeconfig_path[each.key] == "" ? "" : null
    client_key             = local.edges_kubeconfig_path[each.key] == "" ? "" : null
  }
}

provider "kubernetes" {
  alias    = "edge"
  for_each = var.edges

  config_path            = local.edges_kubeconfig_path[each.key] != "" ? local.edges_kubeconfig_path[each.key] : null
  host                   = local.edges_kubeconfig_path[each.key] == "" ? "https://127.0.0.1:0" : null
  cluster_ca_certificate = local.edges_kubeconfig_path[each.key] == "" ? "" : null
  client_certificate     = local.edges_kubeconfig_path[each.key] == "" ? "" : null
  client_key             = local.edges_kubeconfig_path[each.key] == "" ? "" : null
}

provider "helm" {
  alias = "hub"

  kubernetes {
    config_path            = local.hub_kubeconfig_path != "" ? local.hub_kubeconfig_path : null
    host                   = local.hub_kubeconfig_path == "" ? "https://127.0.0.1:0" : null
    cluster_ca_certificate = local.hub_kubeconfig_path == "" ? "" : null
    client_certificate     = local.hub_kubeconfig_path == "" ? "" : null
    client_key             = local.hub_kubeconfig_path == "" ? "" : null
  }
}

provider "kubernetes" {
  alias = "hub"

  config_path            = local.hub_kubeconfig_path != "" ? local.hub_kubeconfig_path : null
  host                   = local.hub_kubeconfig_path == "" ? "https://127.0.0.1:0" : null
  cluster_ca_certificate = local.hub_kubeconfig_path == "" ? "" : null
  client_certificate     = local.hub_kubeconfig_path == "" ? "" : null
  client_key             = local.hub_kubeconfig_path == "" ? "" : null
}
