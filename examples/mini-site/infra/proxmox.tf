# Proxmox hub and client VMs (Ubuntu cloud image, native cloud-init only:
# no snippets, no custom user-data — there is no SSH to the node).
#
# The cloud image ships no qemu-guest-agent; it is installed on the hub by
# k3s-bootstrap (extra_packages). agent.timeout = "10s" keeps create prompt:
# VM create returns promptly instead of waiting ~15 min for an agent that
# exists only after bootstrap.

locals {
  stand_public_key = trimspace(file(pathexpand(var.ssh_public_key_file)))
}

resource "proxmox_virtual_environment_vm" "hub" {
  name        = "${var.env_slug}-hub"
  node_name   = var.proxmox.node_name
  description = "garuda mini-site hub (k3s, Firezone, ipt-server)"

  pool_id         = var.proxmox.pool_id
  stop_on_destroy = true

  agent {
    enabled = true
    timeout = "10s"
  }

  cpu {
    cores = var.proxmox.hub.cores
  }

  memory {
    dedicated = var.proxmox.hub.memory_mb
  }

  disk {
    datastore_id = var.proxmox.datastore_id
    import_from  = var.proxmox.image_file_id
    interface    = "scsi0"
    size         = var.proxmox.hub.disk_gb
  }

  network_device {
    bridge = var.proxmox.bridge
  }

  initialization {
    datastore_id = var.proxmox.datastore_id

    dns {
      servers = var.proxmox.dns_servers
    }

    ip_config {
      ipv4 {
        # /24 with gateway .1 — the stand network contract; confirmed at the
        # first apply by pinging the gateway from the hub.
        address = "${var.proxmox.hub.address}/24"
        gateway = var.proxmox.gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [local.stand_public_key]
    }
  }

  operating_system {
    type = "l26"
  }
}

# Egress-only idle test client: no firewall rules, no NAT — sshd with key-only
# login is its only listener. Not bootstrapped with k3s.
resource "proxmox_virtual_environment_vm" "client" {
  name        = "${var.env_slug}-client"
  node_name   = var.proxmox.node_name
  description = "garuda mini-site smoke client"

  pool_id         = var.proxmox.pool_id
  stop_on_destroy = true

  agent {
    enabled = true
    timeout = "10s"
  }

  cpu {
    cores = var.proxmox.client.cores
  }

  memory {
    dedicated = var.proxmox.client.memory_mb
  }

  disk {
    datastore_id = var.proxmox.datastore_id
    import_from  = var.proxmox.image_file_id
    interface    = "scsi0"
    size         = var.proxmox.client.disk_gb
  }

  network_device {
    bridge = var.proxmox.bridge
  }

  initialization {
    datastore_id = var.proxmox.datastore_id

    dns {
      servers = var.proxmox.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${var.proxmox.client.address}/24"
        gateway = var.proxmox.gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [local.stand_public_key]
    }
  }

  operating_system {
    type = "l26"
  }
}
