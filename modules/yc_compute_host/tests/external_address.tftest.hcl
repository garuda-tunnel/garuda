# Caller-owned external address contracts, with no Yandex Cloud API calls.
mock_provider "yandex" {}

variables {
  name             = "host"
  subnet_id        = "test-subnet"
  env_slug         = "test-env"
  ssh_keys         = []
  external_address = { external_ipv4_address = [{ address = "192.0.2.20", zone_id = "ru-central1-d" }] }
}

# Validates: The caller-owned address is attached and reported.
# Code: main.tf::yandex_compute_instance.this, outputs.tf::public_ipv4, outputs.tf::connection_data
# Assertion: The NIC has NAT on with the supplied address; the output and connection host report it.
# Method: Apply with mock providers and inspect the NIC and outputs.
run "caller_address_attached" {
  command = apply
  assert {
    condition     = yandex_compute_instance.this.network_interface[0].nat && yandex_compute_instance.this.network_interface[0].nat_ip_address == "192.0.2.20"
    error_message = "The supplied address must be attached as one-to-one NAT."
  }
  assert {
    condition     = output.public_ipv4 == "192.0.2.20" && nonsensitive(output.connection_data.host) == "192.0.2.20"
    error_message = "The supplied address must be reported as public_ipv4 and connection_data.host."
  }
}

# Validates: A changed address is passed to the instance.
# Code: main.tf::yandex_compute_instance.this
# Assertion: The NIC contains the new address and the instance ID is unchanged.
# Method: Plan against the preceding mock apply, passing its ID through labels.
#   The mock provider does not evaluate the provider's ForceNew logic, so this
#   pins only that the module adds no replacement trigger of its own; the
#   in-place behaviour of the real provider is documented in variables.tf.
run "change_caller_address" {
  command = plan
  variables {
    external_address = { external_ipv4_address = [{ address = "192.0.2.30", zone_id = "ru-central1-d" }] }
    labels           = { previous_instance_id = run.caller_address_attached.instance_id }
  }
  assert {
    condition     = yandex_compute_instance.this.network_interface[0].nat_ip_address == "192.0.2.30"
    error_message = "The changed address must be attached."
  }
  assert {
    condition     = output.instance_id == var.labels.previous_instance_id
    error_message = "Changing the address must preserve the instance ID."
  }
}

# Validates: A null IP cannot request an ephemeral external address.
# Code: main.tf::yandex_compute_instance.this
# Assertion: A null address fails the instance precondition.
# Method: Plan with a null address and expect the precondition failure.
run "reject_null_address" {
  command = plan
  variables {
    external_address = { external_ipv4_address = [{ address = null, zone_id = "ru-central1-d" }] }
  }
  expect_failures = [yandex_compute_instance.this]
}

# Validates: The address zone matches the VM zone.
# Code: main.tf::yandex_compute_instance.this
# Assertion: A mismatched zone fails the instance precondition.
# Method: Plan with a wrong-zone address and expect the precondition failure.
run "reject_wrong_zone" {
  command = plan
  variables {
    external_address = { external_ipv4_address = [{ address = "192.0.2.20", zone_id = "ru-central1-a" }] }
  }
  expect_failures = [yandex_compute_instance.this]
}

# Validates: An address without an external_ipv4_address block (e.g. an internal-only address) is refused.
# Code: main.tf::yandex_compute_instance.this
# Assertion: Zero blocks fail the instance precondition instead of an index error.
# Method: Plan with an empty block list and expect the precondition failure.
run "reject_zero_blocks" {
  command = plan
  variables {
    external_address = { external_ipv4_address = [] }
  }
  expect_failures = [yandex_compute_instance.this]
}

# Validates: A null block list or null block is refused.
# Code: main.tf::yandex_compute_instance.this
# Assertion: Null shapes fail the instance precondition instead of an index error.
# Method: Plan with a null list and with a null element; expect the precondition failure.
run "reject_null_blocks" {
  command = plan
  variables {
    external_address = { external_ipv4_address = null }
  }
  expect_failures = [yandex_compute_instance.this]
}

run "reject_null_block" {
  command = plan
  variables {
    external_address = { external_ipv4_address = [null] }
  }
  expect_failures = [yandex_compute_instance.this]
}
