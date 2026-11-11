# CNPG database contracts: one `cluster` chart release per app namespace must
# render exactly the inputs the module promises and name the app Secret after
# the cluster. No cluster API calls.
mock_provider "helm" {}

variables {
  namespace     = "firezone"
  database      = "firezone"
  owner         = "firezone"
  image         = "ghcr.io/cloudnative-pg/postgresql:17.11-202611020810-standard-trixie@sha256:4d0aac315c4d8c3202252bd06fea83b16951cc57234a7b610eeaa382ff4482d0"
  chart_version = "0.9.0"
}

# Validates: The rendered chart values express the database contract.
# Code: main.tf::helm_release.database
# Assertion: instances 1, superuser access off, initdb database/owner, storage
#   class/size, digest-pinned image — all exactly the module inputs.
# Method: Plan with mock providers, yamldecode values[0] and compare to inputs.
run "cluster_values_match_inputs" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.database.values[0]).cluster.instances == 1
    error_message = "cluster must run exactly one instance."
  }

  assert {
    condition     = yamldecode(helm_release.database.values[0]).cluster.enableSuperuserAccess == false
    error_message = "enableSuperuserAccess must be false (apps use the -app owner, never postgres)."
  }

  assert {
    condition     = yamldecode(helm_release.database.values[0]).cluster.enablePDB == false
    error_message = "enablePDB must be false: a PDB on a single-instance cluster blocks node drains."
  }

  assert {
    condition     = yamldecode(helm_release.database.values[0]).cluster.annotations["helm.sh/resource-policy"] == "keep"
    error_message = "Cluster must carry helm.sh/resource-policy=keep so release uninstall keeps it and its PVCs."
  }

  assert {
    condition     = yamldecode(helm_release.database.values[0]).cluster.initdb == { database = var.database, owner = var.owner }
    error_message = "initdb must create exactly the requested database and owner."
  }

  assert {
    condition     = yamldecode(helm_release.database.values[0]).cluster.storage == { size = var.storage_size, storageClass = var.storage_class }
    error_message = "storage must be exactly the requested size and class."
  }

  assert {
    condition     = yamldecode(helm_release.database.values[0]).cluster.imageName == var.image
    error_message = "imageName must be the digest-pinned input image."
  }
}

# Validates: Release name and fullname pin the Cluster CR name to var.name.
# Code: main.tf::helm_release.database
# Assertion: release name is var.name, fullnameOverride is var.name, release
#   lives in the caller's namespace and never creates it.
# Method: Plan with mock providers and inspect release arguments plus decoded values.
run "release_name_is_cluster_name" {
  command = plan

  assert {
    condition = alltrue([
      helm_release.database.name == var.name,
      yamldecode(helm_release.database.values[0]).fullnameOverride == var.name,
      helm_release.database.namespace == var.namespace,
      helm_release.database.create_namespace == false,
    ])
    error_message = "release and fullnameOverride must both equal var.name in the caller's namespace."
  }
}

# Validates: Outputs name the Cluster and the CNPG-generated app Secret.
# Code: outputs.tf::cluster_name, outputs.tf::secret_name
# Assertion: default name "postgres" yields cluster postgres and secret postgres-app.
# Method: Plan with mock providers using default variables.
run "secret_name_output" {
  command = plan

  assert {
    condition = alltrue([
      output.cluster_name == "postgres",
      output.secret_name == "postgres-app",
    ])
    error_message = "default name postgres must yield cluster postgres and secret postgres-app."
  }
}

# Validates: A non-DNS-1123 cluster name is rejected at the trust boundary.
# Code: variables.tf::name validation
# Assertion: Plan fails on the name variable.
# Method: Plan with an invalid name and expect the variable validation failure.
run "invalid_name_rejected" {
  command = plan

  variables {
    name = "Postgres_1"
  }

  expect_failures = [var.name]
}

# Validates: An overlong cluster name is rejected at the trust boundary.
# Code: variables.tf::name validation
# Assertion: Plan fails on the name variable when it exceeds 50 chars.
# Method: Plan with a 51-char name and expect the variable validation failure.
run "overlong_name_rejected" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" # 51 chars
  }

  expect_failures = [var.name]
}

# Validates: A non-quantity storage size is rejected at the trust boundary.
# Code: variables.tf::storage_size validation
# Assertion: Plan fails on the storage_size variable.
# Method: Plan with storage_size "2GB" (invalid Kubernetes quantity) and expect the failure.
run "invalid_storage_size_rejected" {
  command = plan

  variables {
    storage_size = "2GB"
  }

  expect_failures = [var.storage_size]
}

# Validates: An empty image is rejected at the trust boundary.
# Code: variables.tf::image validation
# Assertion: Plan fails on the image variable.
# Method: Plan with an empty image and expect the variable validation failure.
run "empty_image_rejected" {
  command = plan

  variables {
    image = ""
  }

  expect_failures = [var.image]
}

# Validates: An empty chart version is rejected at the trust boundary (an empty
# helm version silently installs the latest chart).
# Code: variables.tf::chart_version validation
# Assertion: Plan fails on the chart_version variable.
# Method: Plan with an empty version and expect the variable validation failure.
run "empty_chart_version_rejected" {
  command = plan

  variables {
    chart_version = ""
  }

  expect_failures = [var.chart_version]
}

# Validates: The complete rendered values of the database release are exactly
# the map below. They are byte-for-byte what garuda-internal b12124c4 rendered
# without a backup, so removing the backup and generation support changed no
# deployed release (the migration runbook's plan gates depend on it).
# Code: main.tf::helm_release.database
# Assertion: the decoded values equal the literal map: no extra or missing key.
# Method: Plan with mock providers and compare yamldecode(values[0]) to the map.
run "rendered_values_are_exactly_the_plain_initdb_cluster" {
  command = plan

  assert {
    condition = yamldecode(helm_release.database.values[0]) == {
      fullnameOverride = "postgres"
      cluster = {
        instances             = 1
        imageName             = var.image
        enableSuperuserAccess = false
        enablePDB             = false
        annotations           = { "helm.sh/resource-policy" = "keep" }
        storage               = { size = "2Gi", storageClass = "local-path-retain" }
        initdb                = { database = "firezone", owner = "firezone" }
      }
    }
    error_message = "rendered values must be exactly the plain initdb cluster (no backup, plugin or recovery keys)."
  }
}
