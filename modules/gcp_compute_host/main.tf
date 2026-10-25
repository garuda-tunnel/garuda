# SSH key for the module-managed deploy user. Generated ONLY when the caller
# does not supply ssh_public_key; the external path never creates key material.
# The effective public key goes into metadata["ssh-keys"] together with
# var.ssh_keys; a generated private key is exposed via
# outputs.connection_data.ssh_private_key (null with an external key).
resource "tls_private_key" "admin" {
  count = var.ssh_public_key == null ? 1 : 0

  algorithm = "ED25519"
}

# The resource moved from un-counted to count = 1 when ssh_public_key was
# added; keep existing state (generated keys) without recreation.
moved {
  from = tls_private_key.admin
  to   = tls_private_key.admin[0]
}

# Optional regional static IP
resource "google_compute_address" "this" {
  count   = var.allocate_static_ip ? 1 : 0
  name    = "${local.instance_name}-ext"
  region  = var.region
  project = var.project_id
}

# Firewall (module-managed). Created only when default_ingress or
# ingress_ports is non-empty.
resource "google_compute_firewall" "this" {
  count   = local.firewall_enabled ? 1 : 0
  name    = local.firewall_tag
  network = var.network
  project = var.project_id

  target_tags   = [local.firewall_tag]
  source_ranges = local.ingress_source_cidrs

  dynamic "allow" {
    for_each = concat(local.default_allow_list, local.extra_allow_list)
    content {
      protocol = allow.value.protocol
      ports    = allow.value.ports
    }
  }
}

resource "google_compute_instance" "this" {
  name = local.instance_name
  # GCP requires an FQDN (≥3 labels). The "c.<project>.internal" suffix
  # matches what GCE's auto-generated internal DNS zone uses for the
  # project, so this is a no-op for routing — just makes intent explicit
  # and ensures env_slug shows up in the operator-visible FQDN.
  hostname     = "${local.hostname}.c.${var.project_id}.internal"
  project      = var.project_id
  zone         = var.zone
  machine_type = var.machine_type
  tags         = local.instance_tags
  labels       = var.labels

  allow_stopping_for_update = var.allow_stopping_for_update

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  dynamic "attached_disk" {
    for_each = { for d in var.attached_disks : d.device_name => d }
    content {
      source      = attached_disk.value.disk_id
      device_name = attached_disk.key
      mode        = "READ_WRITE"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = var.allocate_static_ip ? [1] : []
      content {
        nat_ip = var.allocate_static_ip ? google_compute_address.this[0].address : null
      }
    }
  }

  metadata = local.effective_metadata

  # metadata["ssh-keys"] flows through to google-guest-agent (preinstalled
  # on official Ubuntu images). Rotating tls_private_key.admin or
  # var.ssh_keys triggers an in-place metadata update; the agent rewrites
  # per-user authorized_keys within seconds. No reboot required.
  # allow_stopping_for_update must be true for GCP to apply some changes
  # on a running instance (see variables.tf).

  lifecycle {
    # Ignore boot-image drift. Callers typically pass an image *family*
    # URL (e.g. projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts)
    # into var.image; GCE resolves that to the newest concrete image at
    # every plan. Without this, an upstream image publication in the
    # family would flip `boot_disk.initialize_params.image` and force a
    # full instance replacement — destroying the boot disk of stateful
    # hosts with no operator intent. Everything else on the boot_disk
    # block (size, type) still applies in-place normally.
    #
    # Trade-off: a deliberate OS-image refresh now requires an explicit
    # `terragrunt apply -replace=…` (or `tofu taint`). This is the
    # accepted contract — image rollouts are opt-in, not incidental.
    ignore_changes = [boot_disk[0].initialize_params[0].image]
  }
}

