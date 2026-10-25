module "gcp_edges" {
  for_each = var.edges

  source = "./modules/gcp_compute_host"

  name              = each.key
  env_slug          = var.env_slug
  project_id        = var.gcp.project_id
  region            = each.value.region
  zone              = each.value.zone
  machine_type      = each.value.machine_type
  boot_disk_size_gb = each.value.boot_disk_gb

  # k3s-bootstrap preflight asserts Ubuntu 26.04; the module default is 24.04.
  image = var.gcp_image

  ssh_keys = var.operator_ssh_keys

  # The stand key seeds the ubuntu bootstrap user (k3s-bootstrap provisions
  # the garuda admin on top). No module-generated keypair: key content never
  # crosses the module boundary, callers connect with the key by path.
  ssh_user       = "ubuntu"
  ssh_public_key = local.stand_public_key

  allocate_static_ip = true

  # default_ingress opens TCP 22/80/443, UDP 0-65535, ICMP — covers WireGuard.
  default_ingress = true

  labels = {
    garuda_role    = "edge"
    garuda_managed = "terraform"
    garuda_env     = var.env_slug
  }
}
