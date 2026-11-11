# CloudNativePG operator install and shared Retain StorageClass contracts,
# with no cluster API calls.
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  chart_version = "0.29.1"
}

# Validates: The shared StorageClass keeps CNPG PVCs alive when a Cluster is deleted.
# Code: main.tf::kubernetes_storage_class_v1.retain
# Assertion: reclaimPolicy Retain, provisioner rancher.io/local-path, binding WaitForFirstConsumer.
# Method: Plan with mock providers and inspect the StorageClass arguments.
run "storage_class_is_retain" {
  command = plan

  assert {
    condition = alltrue([
      kubernetes_storage_class_v1.retain.reclaim_policy == "Retain",
      kubernetes_storage_class_v1.retain.storage_provisioner == "rancher.io/local-path",
      kubernetes_storage_class_v1.retain.volume_binding_mode == "WaitForFirstConsumer",
      kubernetes_storage_class_v1.retain.metadata[0].name == "local-path-retain",
    ])
    error_message = "local-path-retain must be Retain / rancher.io/local-path / WaitForFirstConsumer."
  }

  assert {
    condition     = output.storage_class_name == "local-path-retain"
    error_message = "storage_class_name output must be local-path-retain."
  }
}

# Validates: The operator release waits in its own namespace so CRDs exist before consumers apply.
# Code: main.tf::helm_release.cnpg
# Assertion: wait is true, release targets (and creates) cnpg-system with the pinned chart version.
# Method: Plan with mock providers and inspect the release arguments.
run "operator_release_waits" {
  command = plan

  assert {
    condition = alltrue([
      helm_release.cnpg.wait == true,
      helm_release.cnpg.namespace == "cnpg-system",
      helm_release.cnpg.create_namespace == true,
      helm_release.cnpg.chart == "cloudnative-pg",
      helm_release.cnpg.version == var.chart_version,
    ])
    error_message = "operator release must wait in a created cnpg-system namespace at the pinned chart version."
  }
}

# Validates: The output is derived from the operator release, so every consumer
# of storage_class_name is implicitly ordered after it.
# Code: outputs.tf::storage_class_name, main.tf::kubernetes_storage_class_v1.retain
# Assertion: the storage class name comes from the resource that depends_on the release.
# Method: Plan with mock providers and compare output values against the
# release/resource attributes (tftest cannot inspect the dependency graph
# itself; value wiring is the observable proxy).
run "outputs_carry_operator_dependency" {
  command = plan

  assert {
    condition     = output.storage_class_name == kubernetes_storage_class_v1.retain.metadata[0].name
    error_message = "storage_class_name must be derived from the StorageClass resource that depends on the operator release."
  }
}

# Validates: An empty chart version is rejected at the trust boundary (an empty
# helm version silently installs the latest chart).
# Code: variables.tf::chart_version validation
# Assertion: Plan fails on the variable.
# Method: Plan with an empty version and expect the variable validation failure.
run "empty_chart_version_rejected" {
  command = plan

  variables {
    chart_version = ""
  }

  expect_failures = [var.chart_version]
}
