# Unit tests for the render. No providers required.

run "default_render_contains_installer_and_bind" {
  command = plan
  assert {
    condition     = strcontains(output.user_data_parts[0], "curl -sfL https://get.k3s.io")
    error_message = "Default install_url and curl pipe must be present."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "--tls-san=127.0.0.1")
    error_message = "Invariant --tls-san=127.0.0.1 must be present."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "--https-listen-port=6443")
    error_message = "Invariant --https-listen-port=6443 must be present."
  }
  assert {
    condition     = !strcontains(output.user_data_parts[0], "--bind-address=")
    error_message = "Stale --bind-address invariant must not appear; the apiserver listens on all interfaces and is constrained by the host firewall."
  }
  assert {
    condition     = !strcontains(output.user_data_parts[0], "--advertise-address=")
    error_message = "--advertise-address must not be set; kubernetes endpoint validation forbids the loopback range for the `kubernetes` service Endpoints, and we have no public IP to advertise."
  }
  assert {
    condition     = startswith(output.user_data_parts[0], "#cloud-config")
    error_message = "Rendered part must start with #cloud-config."
  }
}

run "default_render_disables_bridge_netfilter_for_multus_l2" {
  command = plan
  assert {
    condition     = strcontains(output.user_data_parts[0], "net.bridge.bridge-nf-call-iptables = 0")
    error_message = "k3s nodes must not pass Multus bridge L2 traffic through host iptables."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "net.bridge.bridge-nf-call-ip6tables = 0")
    error_message = "k3s nodes must disable IPv6 bridge netfilter for Multus bridges."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "net.bridge.bridge-nf-call-arptables = 0")
    error_message = "k3s nodes must not pass Multus bridge ARP through host arptables."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "sysctl --system")
    error_message = "cloud-init must apply bridge netfilter sysctls before k3s workloads start."
  }
}

run "version_pinned_emits_install_k3s_version_env" {
  command = plan
  variables {
    k3s_version = "v1.30.5+k3s1"
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "INSTALL_K3S_VERSION=v1.30.5+k3s1")
    error_message = "Pinned version must surface as INSTALL_K3S_VERSION env."
  }
}

run "version_null_omits_env" {
  command = plan
  assert {
    condition     = !strcontains(output.user_data_parts[0], "INSTALL_K3S_VERSION=")
    error_message = "Default (null) version must not emit INSTALL_K3S_VERSION env."
  }
}

run "install_url_override_used" {
  command = plan
  variables {
    install_url = "https://example.net/k3s-install"
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "https://example.net/k3s-install")
    error_message = "Override install_url must surface."
  }
  assert {
    condition     = !strcontains(output.user_data_parts[0], "get.k3s.io")
    error_message = "Default install_url must not leak when overridden."
  }
}

run "extra_flags_appended_after_invariants" {
  command = plan
  variables {
    extra_flags = ["--disable=traefik", "--node-label=role=edge"]
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "--disable=traefik")
    error_message = "extra_flags[0] must surface."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "--node-label=role=edge")
    error_message = "extra_flags[1] must surface."
  }
}

run "extra_install_env_passed_to_curl_pipe" {
  command = plan
  variables {
    extra_install_env = { INSTALL_K3S_CHANNEL = "latest" }
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "INSTALL_K3S_CHANNEL=latest")
    error_message = "extra_install_env entry must surface."
  }
}

run "reject_invalid_version_format" {
  command = plan
  variables {
    k3s_version = "1.30"
  }
  expect_failures = [var.k3s_version]
}

run "reject_non_https_install_url" {
  command = plan
  variables {
    install_url = "http://get.k3s.io"
  }
  expect_failures = [var.install_url]
}

run "reject_extra_flag_without_dashdash" {
  command = plan
  variables {
    extra_flags = ["disable=traefik"]
  }
  expect_failures = [var.extra_flags]
}

run "reject_extra_install_env_non_install_prefix" {
  command = plan
  variables {
    extra_install_env = { K3S_TOKEN = "abc" }
  }
  expect_failures = [var.extra_install_env]
}

run "cloud_init_sets_ip_forward_via_sysctl_drop_in" {
  command = plan
  assert {
    condition     = strcontains(output.user_data_parts[0], "99-garuda-ip-forward.conf")
    error_message = "cloud-init must write the 99-garuda-ip-forward.conf sysctl drop-in (replaces linux_host_prerequisites)."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "net.ipv4.ip_forward = 1")
    error_message = "99-garuda-ip-forward.conf must contain net.ipv4.ip_forward = 1."
  }
}

run "cloud_init_provisions_guarded_swapfile" {
  command = plan
  assert {
    condition     = strcontains(output.user_data_parts[0], "99-garuda-swap.conf")
    error_message = "cloud-init must write the 99-garuda-swap.conf sysctl drop-in."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "vm.swappiness = 30")
    error_message = "99-garuda-swap.conf must set vm.swappiness = 30."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048")
    error_message = "runcmd must create /swapfile, falling back to dd when fallocate is unsupported."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "mkswap /swapfile")
    error_message = "runcmd must format /swapfile as swap."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "swapon /swapfile")
    error_message = "runcmd must activate /swapfile."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab")
    error_message = "runcmd must persist /swapfile in /etc/fstab exactly once (idempotent append)."
  }
}

run "cni_reload_start_is_nonblocking_and_checked" {
  command = plan
  assert {
    condition     = strcontains(output.user_data_parts[0], "systemctl start --no-block garuda-k3s-cni-reload.service")
    error_message = "cni-reload unit must be started with 'systemctl start --no-block' so runcmd does not stall waiting for the (up to 10 min) reload, while still surfacing systemctl start failures instead of the fire-and-forget shell '&' form that silently swallows them."
  }
  assert {
    condition     = !strcontains(output.user_data_parts[0], "garuda-k3s-cni-reload.service &")
    error_message = "The fire-and-forget shell backgrounding form ('... .service &') must not reappear; it swallows systemctl start errors."
  }
}
