# Caller-owned external address contracts, with no Google API calls.
mock_provider "google" {}

variables {
  name             = "host"
  project_id       = "test-project"
  region           = "us-central1"
  zone             = "us-central1-a"
  env_slug         = "test-env"
  ssh_keys         = []
  external_address = { address = "192.0.2.20", region = "us-central1", address_type = "EXTERNAL" }
}

# Validates: The caller-owned address is attached and reported.
# Code: main.tf::google_compute_instance.this, outputs.tf::public_ipv4
# Assertion: The NIC and output contain the supplied address.
# Method: Apply with mock providers and inspect the NIC and output.
run "caller_address_attached" {
  command = apply
  assert {
    condition     = google_compute_instance.this.network_interface[0].access_config[0].nat_ip == var.external_address.address && output.public_ipv4 == var.external_address.address
    error_message = "The supplied address must be attached and reported."
  }
}

# Validates: A changed address is passed to the instance.
# Code: main.tf::google_compute_instance.this
# Assertion: The NIC contains the new address and the instance ID is unchanged.
# Method: Plan against the preceding mock apply, passing its ID through labels.
run "change_caller_address" {
  command = plan
  variables {
    external_address = { address = "192.0.2.30", region = "us-central1", address_type = "EXTERNAL" }
    labels           = { previous_instance_id = run.caller_address_attached.instance_id }
  }
  assert {
    condition     = google_compute_instance.this.network_interface[0].access_config[0].nat_ip == var.external_address.address
    error_message = "The changed address must be attached."
  }
  assert {
    condition     = output.instance_id == var.labels.previous_instance_id
    error_message = "Changing the address must preserve the instance ID."
  }
}

# Validates: A null IP cannot request an ephemeral external address.
# Code: main.tf::google_compute_instance.this
# Assertion: A null address fails the instance precondition.
# Method: Plan with a null address and expect the precondition failure.
run "reject_null_address" {
  command = plan
  variables {
    external_address = { address = null, region = "us-central1", address_type = "EXTERNAL" }
  }
  expect_failures = [google_compute_instance.this]
}

# Validates: The address region matches the VM region.
# Code: main.tf::google_compute_instance.this
# Assertion: A mismatched region fails the instance precondition.
# Method: Plan with a wrong-region address and expect the precondition failure.
run "reject_wrong_region" {
  command = plan
  variables {
    external_address = { address = "192.0.2.20", region = "us-east1", address_type = "EXTERNAL" }
  }
  expect_failures = [google_compute_instance.this]
}

# Validates: The address is external.
# Code: main.tf::google_compute_instance.this
# Assertion: An internal address fails the instance precondition.
# Method: Plan with an internal address and expect the precondition failure.
run "reject_internal_address" {
  command = plan
  variables {
    external_address = { address = "192.0.2.20", region = "us-central1", address_type = "INTERNAL" }
  }
  expect_failures = [google_compute_instance.this]
}
