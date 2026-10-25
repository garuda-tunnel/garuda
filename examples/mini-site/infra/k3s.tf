# k3s on the hub and both GCP edges via k3s-bootstrap (controller-side
# Ansible over SSH; replaces the old k3s_cloud_init user-data). Each node is
# a single-member cluster (node_type = "initial"). The Proxmox client is not
# a cluster node and is not bootstrapped.

locals {
  # Every host the controller SSHes to: the bootstrapped nodes plus the
  # (not bootstrapped) idle test client, so its host key is verified too.
  keyscan_targets = merge(
    {
      hub = {
        host            = var.proxmox.hub.address
        host_generation = proxmox_virtual_environment_vm.hub.id
      }
      client = {
        host            = var.proxmox.client.address
        host_generation = proxmox_virtual_environment_vm.client.id
      }
    },
    {
      for k, m in module.gcp_edges : k => {
        host            = m.public_ipv4
        host_generation = m.instance_id
      }
    },
  )

  k3s_nodes = {
    for k, v in local.keyscan_targets : k => merge(v, {
      # The Proxmox cloud image ships no guest agent; bootstrap installs it.
      extra_packages = k == "hub" ? ["qemu-guest-agent"] : []
    }) if k != "client"
  }
}

# Trust-on-first-use host keys: after each host exists, ssh-keyscan it into
# the stand known_hosts file (dedup by exact first-field host match).
#
# k3s-bootstrap itself only adds -o StrictHostKeyChecking=yes — it has no
# known_hosts input. The scanned file takes effect through the operator
# environment: export
#   ANSIBLE_SSH_ARGS="-o UserKnownHostsFile=<absolute known_hosts_file>"
# (plus keepalives as desired), exactly like the local stand's ./stand
# wrapper. The operator's terragrunt wrapper wires this.
resource "terraform_data" "known_hosts" {
  for_each = local.keyscan_targets

  # generation = VM id / instance id: a replaced host is re-scanned. host is
  # included so a replaced static address re-keys too.
  triggers_replace = [each.value.host, each.value.host_generation]

  provisioner "local-exec" {
    environment = {
      KH_HOST = each.value.host
      KH_ROLE = each.key
      KH_FILE = abspath(pathexpand(var.known_hosts_file))
    }

    command = <<-EOT
      set -eu
      for tool in ssh-keyscan flock; do
        command -v "$tool" >/dev/null 2>&1 || {
          echo "$tool not found on the controller (see infra README prerequisites)" >&2
          exit 1
        }
      done
      scan="$(mktemp)"
      ok=""
      # Bounded retry: 19 x (10s keyscan timeout + 5s sleep) < 5 min, then fail
      # with a clear message instead of hanging (wrong gateway/prefix symptom).
      i=0
      while [ "$i" -lt 19 ]; do
        if ssh-keyscan -T 10 -p 22 "$KH_HOST" > "$scan" 2>/dev/null && [ -s "$scan" ]; then
          ok=1
          break
        fi
        i=$((i + 1))
        sleep 5
      done
      if [ -z "$ok" ]; then
        echo "host $KH_ROLE ($KH_HOST) unreachable on 22: check gateway/prefix" >&2
        rm -f "$scan"
        exit 1
      fi
      touch "$KH_FILE"
      # shortcut: per-host whole-file rewrite under flock; per-host merge only if scans ever contend beyond apply time
      (
        flock 9
        awk -v h="$KH_HOST" '$1 != h' "$KH_FILE" > "$KH_FILE.tmp"
        cat "$scan" >> "$KH_FILE.tmp"
        mv "$KH_FILE.tmp" "$KH_FILE"
      ) 9>>"$KH_FILE.lock"
      rm -f "$scan"
    EOT
  }
}

module "k3s" {
  for_each   = local.k3s_nodes
  source     = "git::https://github.com/garuda-tunnel/k3s-bootstrap-internal.git?ref=v0.2.0"
  depends_on = [terraform_data.known_hosts]

  node_type            = "initial"
  host                 = each.value.host
  host_generation      = each.value.host_generation
  bootstrap_user       = "ubuntu"
  ssh_user             = "garuda"
  ssh_private_key_file = var.ssh_private_key_file
  authorized_keys      = [local.stand_public_key]
  k3s_version          = var.k3s_version
  firewall_mode        = "managed"
  cluster_cidrs        = var.cluster_cidrs
  api_trusted_cidrs    = var.api_trusted_cidrs
  extra_packages       = each.value.extra_packages

  # The WireGuard/FRR pods set these pod-scope sysctls; kubelet flags them
  # unsafe unless allow-listed at install time (the same set the retired
  # k3s_cloud_init module seeded). tls-san 127.0.0.1 is added by the module.
  k3s_config = {
    "kubelet-arg" = ["allowed-unsafe-sysctls=net.ipv4.ip_forward,net.ipv4.conf.all.src_valid_mark,net.ipv4.conf.all.rp_filter"]
  }
}
