mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "time" {}

variables {
  namespace       = "garuda"
  backbone_subnet = "10.42.0.0/24"
  border_subnet   = "10.43.0.0/24"
}

run "garuda_chart_path_resolves_to_bundled_chart" {
  command = plan

  assert {
    condition     = endswith(helm_release.garuda.chart, "/charts/garuda")
    error_message = "helm_release.garuda.chart must point at ${path.module}/charts/garuda"
  }
}

run "garuda_cni_chart_path_resolves_to_bundled_chart" {
  command = plan

  assert {
    condition     = endswith(helm_release.garuda_cni.chart, "/charts/garuda-cni")
    error_message = "helm_release.garuda_cni.chart must point at ${path.module}/charts/garuda-cni"
  }
}

run "garuda_cni_waits_for_ready" {
  command = plan

  # The split exists because the NAD CRD is registered at runtime by the
  # Multus DS. wait=true is what guarantees the CRD is observable by the
  # time the dependent helm_release.garuda runs. Regression-locked here.
  assert {
    condition     = helm_release.garuda_cni.wait == true
    error_message = "helm_release.garuda_cni.wait must be true so the Multus CRD exists before the main chart applies NADs."
  }
}

run "namespace_propagates_to_both_releases" {
  command = plan

  variables {
    namespace = "garuda-pt"
  }

  assert {
    condition     = helm_release.garuda.namespace == "garuda-pt"
    error_message = "helm_release.garuda.namespace must echo var.namespace"
  }

  assert {
    condition     = helm_release.garuda_cni.namespace == "garuda-pt"
    error_message = "helm_release.garuda_cni.namespace must echo var.namespace"
  }
}

# Reloader is the secret-rollout mechanism for consumer Deployments: it must be
# pinned to this module namespace (Role/RoleBinding RBAC, never a ClusterRole
# on Secrets) and watch only Secrets via the reload annotation. The version is
# written literally in main.tf under the Renovate annotation so repin works.
run "reloader_is_namespace_scoped" {
  command = plan

  assert {
    condition     = helm_release.reloader.repository == "oci://ghcr.io/stakater/charts"
    error_message = "helm_release.reloader.repository must be the Stakater OCI chart repo."
  }

  assert {
    condition     = helm_release.reloader.chart == "reloader"
    error_message = "helm_release.reloader.chart must be reloader."
  }

  assert {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", helm_release.reloader.version))
    error_message = "helm_release.reloader.version must be an exact X.Y.Z pin (Renovate repins it in main.tf)"
  }

  assert {
    condition     = helm_release.reloader.namespace == var.namespace
    error_message = "helm_release.reloader.namespace must echo var.namespace so its RBAC scope matches the consumer workloads."
  }

  assert {
    condition = yamldecode(helm_release.reloader.values[0]).reloader == {
      watchGlobally    = false
      reloadStrategy   = "annotations"
      ignoreConfigMaps = true
    }
    error_message = "reloader values must be exactly watchGlobally=false (namespace Role, no ClusterRole), reloadStrategy=annotations, ignoreConfigMaps=true."
  }
}

run "reloader_follows_namespace" {
  command = plan

  variables {
    namespace = "garuda-pt"
  }

  assert {
    condition     = helm_release.reloader.namespace == "garuda-pt"
    error_message = "helm_release.reloader.namespace must echo a non-default var.namespace; consumers rely on it being scoped to their namespace."
  }
}

run "garuda_values_include_subnets" {
  command = plan

  variables {
    namespace       = "garuda-pt"
    backbone_subnet = "10.142.0.0/24"
    border_subnet   = "10.143.0.0/24"
    install_cni     = false
  }

  assert {
    condition     = strcontains(helm_release.garuda.values[0], "\"namespace\": \"garuda-pt\"")
    error_message = "rendered garuda values must contain namespace from var.namespace"
  }

  assert {
    condition     = strcontains(helm_release.garuda.values[0], "\"backboneSubnet\": \"10.142.0.0/24\"")
    error_message = "rendered garuda values must contain backboneSubnet from var.backbone_subnet"
  }

  assert {
    condition     = strcontains(helm_release.garuda.values[0], "\"borderSubnet\": \"10.143.0.0/24\"")
    error_message = "rendered garuda values must contain borderSubnet from var.border_subnet"
  }

  # The garuda chart no longer ships CNI manifests; installCni belongs to
  # garuda_cni only.
  assert {
    condition     = !strcontains(helm_release.garuda.values[0], "installCni")
    error_message = "garuda chart values must not contain installCni; it belongs to the garuda-cni chart."
  }
}

run "garuda_cni_values_carry_install_cni_flag" {
  command = plan

  variables {
    namespace   = "garuda-pt"
    install_cni = false
  }

  assert {
    condition     = strcontains(helm_release.garuda_cni.values[0], "\"namespace\": \"garuda-pt\"")
    error_message = "rendered garuda-cni values must contain namespace from var.namespace"
  }

  assert {
    condition     = strcontains(helm_release.garuda_cni.values[0], "\"installCni\": false")
    error_message = "rendered garuda-cni values must contain installCni from var.install_cni"
  }
}

run "outputs_with_default_namespace" {
  command = plan

  assert {
    condition     = output.namespace == "garuda"
    error_message = "output.namespace must echo var.namespace"
  }

  assert {
    condition     = output.backbone_nad_name == "backbone"
    error_message = "output.backbone_nad_name must be the static value 'backbone'"
  }

  assert {
    condition     = output.border_nad_name == "border"
    error_message = "output.border_nad_name must be the static value 'border'"
  }
}

run "output_namespace_echoes_custom_value" {
  command = plan

  variables {
    namespace = "garuda-pt"
  }

  assert {
    condition     = output.namespace == "garuda-pt"
    error_message = "output.namespace must echo a non-default var.namespace; this is the contract wireguard/kube consumes."
  }
}

run "invalid_namespace_rejected" {
  command = plan

  variables {
    namespace = "Garuda_Bad"
  }

  expect_failures = [var.namespace]
}

run "invalid_backbone_subnet_rejected" {
  command = plan

  variables {
    backbone_subnet = "not-a-cidr"
  }

  expect_failures = [var.backbone_subnet]
}

# Phase 3 (Task 8): assert that output.map_propagation_id is exposed for consumer modules.
# time_sleep.map_propagation is mocked by mock_provider "time".
run "map_propagation_output_present" {
  command = plan

  assert {
    condition     = output.map_propagation_id != null
    error_message = "map_propagation_id output must be exposed so stand-level workload modules can depend on it (Phase 5 wiring)"
  }
}

# Phase 3 (Task 8): assert that time_sleep.map_propagation uses the correct duration.
run "map_propagation_duration_10s" {
  command = plan

  assert {
    condition     = time_sleep.map_propagation.create_duration == "10s"
    error_message = "time_sleep.map_propagation.create_duration must be 10s (2x observed ~3-5s propagation latency — spec §8.3)"
  }
}

# Phase 3 (Task 8): belt-and-suspenders — verify map_propagation_id is non-empty
# (proves the resource is created and wired into the plan).
run "map_propagation_id_non_empty_string" {
  command = plan

  assert {
    condition     = output.map_propagation_id != ""
    error_message = "map_propagation_id must not be an empty string; time_sleep.map_propagation must be in the plan"
  }
}

run "pod_reaper_default_leaves_chart_values_alone" {
  command = plan

  assert {
    condition     = !strcontains(helm_release.garuda.values[0], "podReaper")
    error_message = "without pod_reaper_max_unready the rendered values must not mention podReaper (chart default 120s applies)"
  }
}

run "pod_reaper_max_unready_overrides_only_that_key" {
  command = plan

  variables {
    pod_reaper_max_unready = "600s"
  }

  assert {
    condition     = yamldecode(helm_release.garuda.values[0]).podReaper == { maxUnready = "600s" }
    error_message = "pod_reaper_max_unready must render exactly podReaper.maxUnready"
  }
}

run "pod_reaper_max_unready_rejects_bad_duration" {
  command = plan

  variables {
    pod_reaper_max_unready = "soon"
  }

  expect_failures = [var.pod_reaper_max_unready]
}

# mtu_policy feeds the garuda chart's borderMtu (the border NAD's bridge mtu):
# the site_mtu form must yield site_mtu, the explicit form effective_mtu.
run "mtu_policy_default_feeds_border_nad_mtu" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.garuda.values[0]).borderMtu == 1330
    error_message = "mtu_policy default { site_mtu = 1330 } must render the border NAD mtu as 1330."
  }
}

run "mtu_policy_effective_mtu_feeds_border_nad_mtu" {
  command = plan

  variables {
    mtu_policy = {
      effective_mtu = 1400
      fixed_mss     = 1360
    }
  }

  assert {
    condition     = yamldecode(helm_release.garuda.values[0]).borderMtu == 1400
    error_message = "explicit mtu_policy form must render effective_mtu (not fixed_mss) as the border NAD mtu."
  }
}

run "mtu_policy_rejects_invalid_combo" {
  command = plan

  variables {
    mtu_policy = {
      site_mtu      = 1330
      effective_mtu = 1400
      fixed_mss     = 1360
    }
  }

  expect_failures = [var.mtu_policy]
}
