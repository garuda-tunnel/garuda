# PRECOMPUTED profile-rev HASHES
# These tests assert exact sha256 values because OpenTofu 1.12.3 does not
# support cross-run output references (run.<name>.output.*).
# To regenerate after intentionally changing the hashed intent field set:
#   1) cd modules/garuda_guest
#   2) Create /tmp/compute_hash/main.tf with a single output that calls:
#        sha256("${sha256(jsonencode({ <all intent fields at their new defaults> }))}:<garuda_chart_version>")
#      Match the exact field order in main.tf local.intent_hash.
#   3) tofu init -backend=false && tofu apply -auto-approve
#   4) Paste the resulting 64-char hashes into this file.
# The baseline assertion in run "profile_rev_baseline" is the canary: if it
# fails, the intent field set changed and ALL hashes below must be regenerated.

variables {
  profile              = "ospf-router"
  ospf_router_id       = "10.130.30.22"
  networks             = ["backbone", "border"]
  garuda_chart_version = "0.6.0"
}

run "rejects_unknown_profile" {
  command = plan
  variables {
    profile = "not-a-profile"
  }
  expect_failures = [var.profile]
}

run "accepts_valid_profile" {
  command = plan
  assert {
    condition     = output.labels["net.garuda-tunnel/profile"] == "ospf-router"
    error_message = "profile label must equal the input profile"
  }
}

run "composes_networks_form_a" {
  command = plan
  assert {
    condition     = output.annotations["k8s.v1.cni.cncf.io/networks"] == "backbone@backbone,border@border"
    error_message = "fabric NADs must compose to name@iface CSV"
  }
}

run "prepends_workload_nads" {
  command = plan
  variables {
    workload_nads = ["wg-firezone"]
    networks      = ["backbone", "border"]
  }
  assert {
    condition     = output.annotations["k8s.v1.cni.cncf.io/networks"] == "wg-firezone,backbone@backbone,border@border"
    error_message = "workload NADs must be joined before fabric NADs"
  }
}

run "rejects_unknown_network" {
  command = plan
  variables {
    networks = ["backbone", "wan0"]
  }
  expect_failures = [var.networks]
}

run "rejects_empty_networks" {
  command = plan
  variables {
    networks = []
  }
  expect_failures = [var.networks]
}

run "rejects_duplicate_networks" {
  command = plan
  variables {
    networks = ["backbone", "backbone"]
  }
  expect_failures = [var.networks]
}

run "rejects_duplicate_workload_nads" {
  command = plan
  variables {
    workload_nads = ["wg-firezone", "wg-firezone"]
  }
  expect_failures = [var.workload_nads]
}

run "transit_provider_xor_rejects_transit_interfaces" {
  command = plan
  variables {
    profile            = "transit-provider"
    transit_interfaces = "wg-firezone"
  }
  expect_failures = [var.transit_interfaces]
}

run "raw_mode_requires_raw_configmap" {
  command = plan
  variables {
    frr_mode          = "raw"
    frr_raw_configmap = ""
  }
  expect_failures = [var.frr_mode]
}

run "raw_mode_forbids_interfaces" {
  command = plan
  variables {
    frr_mode          = "raw"
    frr_raw_configmap = "wg-hub-ros-frr-raw"
    interfaces        = "backbone"
  }
  expect_failures = [var.frr_mode]
}

run "raw_mode_forbids_extra_configmap" {
  command = plan
  variables {
    frr_mode            = "raw"
    frr_raw_configmap   = "wg-hub-ros-frr-raw"
    frr_extra_configmap = "wg-hub-ros-frr-extra"
  }
  expect_failures = [var.frr_mode]
}

run "rejects_bad_router_id" {
  command = plan
  variables {
    ospf_router_id = "not-an-ip"
  }
  expect_failures = [var.ospf_router_id]
}

run "omits_empty_optional_annotations" {
  command = plan
  assert {
    condition     = !contains(keys(output.annotations), "net.garuda-tunnel/redistribute")
    error_message = "empty redistribute must NOT emit an annotation key"
  }
}

run "emits_router_id_when_set" {
  command = plan
  assert {
    condition     = output.annotations["net.garuda-tunnel/router-id"] == "10.130.30.22"
    error_message = "router-id annotation must be emitted when set"
  }
}

run "profile_rev_baseline" {
  command = plan
  assert {
    condition     = length(output.annotations["net.garuda-tunnel/profile-rev"]) == 64
    error_message = "profile-rev must be a 64-char sha256 hex string"
  }
  assert {
    condition     = output.annotations["net.garuda-tunnel/profile-rev"] == "50ccfb1f4c5e1294acb2a387e22c9162f2b6f0b0b4aca2e6f271b304fc98c22a"
    error_message = "baseline profile-rev changed — regenerate ALL precomputed hashes in this file (see header recipe). A change here usually means the hashed intent field set changed."
  }
}

run "profile_rev_changes_with_intent" {
  command = plan
  variables {
    redistribute = "connected"
  }
  assert {
    # Baseline (redistribute="") produces 50ccfb1f4c5e1294...; redistributed must differ.
    condition     = output.annotations["net.garuda-tunnel/profile-rev"] == "e6b97a99e10d28680ee947b8ca2cb0b17695df3d844e32605cdccbe50694518b"
    error_message = "changing redistribute MUST change profile-rev (expected e6b97a99e10d2868...)"
  }
  assert {
    condition     = output.annotations["net.garuda-tunnel/profile-rev"] != "50ccfb1f4c5e1294acb2a387e22c9162f2b6f0b0b4aca2e6f271b304fc98c22a"
    error_message = "changing redistribute MUST produce a different profile-rev than the baseline"
  }
}

run "profile_rev_changes_with_chart_version" {
  command = plan
  variables {
    garuda_chart_version = "0.7.0"
  }
  assert {
    # chart_version=0.7.0 must produce a different hash than baseline (0.6.0 → 50ccfb1f4c5e1294...).
    condition     = output.annotations["net.garuda-tunnel/profile-rev"] == "96a110e085c0e33d47ec288b41b7206572edafeb8324fd3578d4162854e4bb46"
    error_message = "changing garuda_chart_version MUST change profile-rev (expected 96a110e085c0e33d...)"
  }
  assert {
    condition     = output.annotations["net.garuda-tunnel/profile-rev"] != "50ccfb1f4c5e1294acb2a387e22c9162f2b6f0b0b4aca2e6f271b304fc98c22a"
    error_message = "changing garuda_chart_version MUST produce a different profile-rev than the baseline"
  }
}

run "profile_rev_changes_with_configmap_content" {
  command = plan
  variables {
    configmaps = { "wg-frr-extra" = { "extra.conf" = "ip forwarding" } }
  }
  assert {
    # Non-empty configmaps must shift the hash away from the empty-configmaps baseline (50ccfb1f4c5e1294...).
    condition     = output.annotations["net.garuda-tunnel/profile-rev"] == "8973e116e1c63d107f78fed8caadab8b4c6d4746dab6c5436b2148dd8d36890b"
    error_message = "changing configmaps content MUST change profile-rev (expected 8973e116e1c63d10...; sidecar renders at start only)"
  }
  assert {
    condition     = output.annotations["net.garuda-tunnel/profile-rev"] != "50ccfb1f4c5e1294acb2a387e22c9162f2b6f0b0b4aca2e6f271b304fc98c22a"
    error_message = "changing configmaps content MUST produce a different profile-rev than the baseline"
  }
}

run "omits_empty_mtu_annotation" {
  command = plan
  assert {
    condition     = !contains(keys(output.annotations), "net.garuda-tunnel/mtu")
    error_message = "unset mtu must NOT emit an annotation key"
  }
}

run "omits_empty_passive_interfaces_annotation" {
  command = plan
  assert {
    condition     = !contains(keys(output.annotations), "net.garuda-tunnel/passive-interfaces")
    error_message = "unset passive_interfaces must NOT emit an annotation key"
  }
}

run "emits_passive_interfaces_when_set" {
  command = plan
  variables {
    passive_interfaces = "wg-firezone"
  }
  assert {
    condition     = output.annotations["net.garuda-tunnel/passive-interfaces"] == "wg-firezone"
    error_message = "passive-interfaces annotation must be emitted when set"
  }
}
