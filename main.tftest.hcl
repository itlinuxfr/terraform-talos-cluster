# Validates that the plan can be generated with valid inputs
run "valid_plan" {
  command = plan

  variables {
    talos_cluster_name = "test-cluster"
    talos_vip          = "192.168.1.10"
    talos_controlplanes = {
      "cp1" = {
        ip        = "192.168.1.11"
        hostname  = "cp1"
        interface = "eth0"
        disk      = "/dev/vda"
      }
    }
    talos_workernodes = {
      "worker1" = {
        ip        = "192.168.1.12"
        hostname  = "worker1"
        interface = "eth0"
        disk      = "/dev/vda"
      }
    }
  }

  assert {
    condition     = talos_machine_secrets.this.talos_version == "v1.11.3"
    error_message = "Default talos version did not match expected"
  }
}

# Validates that invalid talos version triggers validation error
run "invalid_version" {
  command = plan

  variables {
    talos_cluster_name  = "test-cluster"
    talos_vip           = "192.168.1.10"
    talos_version       = "invalid-version"
    talos_controlplanes = {}
    talos_workernodes   = {}
  }

  expect_failures = [
    var.talos_version
  ]
}

# Validates that invalid IP triggers validation error
run "invalid_ip" {
  command = plan

  variables {
    talos_cluster_name  = "test-cluster"
    talos_vip           = "invalid-ip"
    talos_controlplanes = {}
    talos_workernodes   = {}
  }

  expect_failures = [
    var.talos_vip
  ]
}
