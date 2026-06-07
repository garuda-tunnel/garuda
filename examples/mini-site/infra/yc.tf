# Default VPC and the primary subnet are pre-existing — consumed as data.
data "yandex_vpc_network" "default" {
  network_id = var.yc.network_id
}

data "yandex_vpc_subnet" "primary" {
  subnet_id = var.yc.primary_subnet_id
}

# Caller-owned data disk for the hub. Lifecycle is decoupled from the VM:
# recreating the VM module does not touch this resource.
resource "yandex_compute_disk" "hub_data" {
  count = var.hub.existing_disk_id == null ? 1 : 0

  name = "${var.env_slug}-hub-data"
  zone = var.yc.zone
  type = "network-ssd"
  size = var.hub.data_disk_gb

  labels = {
    garuda_role    = "hub"
    garuda_managed = "terraform"
    garuda_env     = var.env_slug
  }

  lifecycle {
    prevent_destroy = false # mini-site is disposable; production stacks should set true
  }
}

locals {
  hub_disk_id = var.hub.existing_disk_id != null ? var.hub.existing_disk_id : yandex_compute_disk.hub_data[0].id
}

module "k3s_init_hub" {
  source = "./modules/k3s_cloud_init"

  # Same pod-level sysctls already allow-listed for edge WireGuard/FRR
  # workloads in gcp.tf (`module.k3s_init_edges`). The kubelet flags
  # this set as unsafe; without the allow-list the wireguard/kube pod
  # lands in SysctlForbidden and the helm_release wait times out.
  extra_flags = [
    "--kubelet-arg=allowed-unsafe-sysctls=net.ipv4.ip_forward,net.ipv4.conf.all.src_valid_mark,net.ipv4.conf.all.rp_filter",
  ]
}

module "yc_hub" {
  source = "./modules/yc_compute_host"

  name       = "hub"
  env_slug   = var.env_slug
  zone       = var.yc.zone
  subnet_id  = data.yandex_vpc_subnet.primary.id
  network_id = data.yandex_vpc_network.default.id

  cores             = var.hub.cores
  memory_gb         = var.hub.memory_gb
  boot_disk_size_gb = var.hub.boot_disk_gb

  attached_disks = [
    {
      disk_id     = local.hub_disk_id
      device_name = "garuda-data"
      mount_path  = "/opt/garuda"
    },
  ]

  ssh_keys = var.operator_ssh_keys

  user_data_parts = module.k3s_init_hub.user_data_parts

  # default_ingress opens TCP 22/80/443, UDP 0-65535, ICMP — covers all
  # WireGuard tunnels and Firezone UDP 51620.
  default_ingress = true

  labels = {
    garuda_role    = "hub"
    garuda_managed = "terraform"
    garuda_env     = var.env_slug
  }
}
