# Resources required on a fresh RouterOS install before any other module
# can usefully apply. These were previously in vpn2/main.tf and moved here
# because they belong to the infra layer (bootstrap primitives, not
# workloads). Count-gated by routeros_enabled; stands without RouterOS
# (the Proxmox stand) plan zero resources here.

resource "routeros_interface_list" "lan" {
  count = var.routeros_enabled ? 1 : 0

  name    = "LAN"
  comment = "garuda"
}

resource "routeros_ip_dns" "this" {
  count = var.routeros_enabled ? 1 : 0

  servers = ["1.1.1.1", "8.8.8.8"]
}
