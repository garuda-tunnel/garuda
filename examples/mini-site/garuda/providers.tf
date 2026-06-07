provider "routeros" {
  hosturl  = "api://${var.routeros.management_host}"
  username = var.routeros.user
  password = var.routeros_password
  insecure = true
}

# --- Edge k3s providers: one explicit alias per edge slug. ---
#
# Each alias is fed by local.edges_kubeconfig_path[<slug>] from the
# garuda-tunnel state file. Under variant C of the migration (see
# spec 2026-05-30-garuda-tunnel-kube-targets-migration-design.md),
# garuda-tunnel materializes a fully patched kubeconfig per node:
# server: is rewritten to the local forwarded port, tls-server-name is
# set from the SAN probe, and the embedded CA/cert/key match. So a
# single config_path is sufficient.
#
# Inert branch: when the path is "" (mock-state, tofu test), we set
# config_path = null AND pin host to an unreachable loopback port with
# empty cert material. This stops the kubernetes/helm providers from
# falling back to $KUBECONFIG / ~/.kube/config.

provider "helm" {
  alias = "pt"

  kubernetes {
    config_path            = local.edges_kubeconfig_path["pt"] != "" ? local.edges_kubeconfig_path["pt"] : null
    host                   = local.edges_kubeconfig_path["pt"] == "" ? "https://127.0.0.1:0" : null
    cluster_ca_certificate = local.edges_kubeconfig_path["pt"] == "" ? "" : null
    client_certificate     = local.edges_kubeconfig_path["pt"] == "" ? "" : null
    client_key             = local.edges_kubeconfig_path["pt"] == "" ? "" : null
  }
}

provider "kubernetes" {
  alias = "pt"

  config_path            = local.edges_kubeconfig_path["pt"] != "" ? local.edges_kubeconfig_path["pt"] : null
  host                   = local.edges_kubeconfig_path["pt"] == "" ? "https://127.0.0.1:0" : null
  cluster_ca_certificate = local.edges_kubeconfig_path["pt"] == "" ? "" : null
  client_certificate     = local.edges_kubeconfig_path["pt"] == "" ? "" : null
  client_key             = local.edges_kubeconfig_path["pt"] == "" ? "" : null
}

provider "helm" {
  alias = "de"

  kubernetes {
    config_path            = local.edges_kubeconfig_path["de"] != "" ? local.edges_kubeconfig_path["de"] : null
    host                   = local.edges_kubeconfig_path["de"] == "" ? "https://127.0.0.1:0" : null
    cluster_ca_certificate = local.edges_kubeconfig_path["de"] == "" ? "" : null
    client_certificate     = local.edges_kubeconfig_path["de"] == "" ? "" : null
    client_key             = local.edges_kubeconfig_path["de"] == "" ? "" : null
  }
}

provider "kubernetes" {
  alias = "de"

  config_path            = local.edges_kubeconfig_path["de"] != "" ? local.edges_kubeconfig_path["de"] : null
  host                   = local.edges_kubeconfig_path["de"] == "" ? "https://127.0.0.1:0" : null
  cluster_ca_certificate = local.edges_kubeconfig_path["de"] == "" ? "" : null
  client_certificate     = local.edges_kubeconfig_path["de"] == "" ? "" : null
  client_key             = local.edges_kubeconfig_path["de"] == "" ? "" : null
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
