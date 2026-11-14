# Input validation tests: each rejected value must fail the plan on the right variable.

mock_provider "talos" {}

variables {
  cluster_name       = "demo"
  cluster_endpoint   = "https://192.0.2.2:6443"
  kubernetes_version = "v1.37.2"
  nodes = {
    "cp-1"     = { role = "controlplane", ip = "192.0.2.3" }
    "worker-1" = { role = "worker", ip = "192.0.2.6" }
  }
}

run "uppercase_cluster_name_refused" {
  command = plan
  variables {
    cluster_name = "Demo"
  }
  expect_failures = [var.cluster_name]
}

run "plain_http_endpoint_refused" {
  command = plan
  variables {
    cluster_endpoint = "http://192.0.2.2:6443"
  }
  expect_failures = [var.cluster_endpoint]
}

run "endpoint_without_scheme_refused" {
  command = plan
  variables {
    cluster_endpoint = "192.0.2.2:6443"
  }
  expect_failures = [var.cluster_endpoint]
}

run "kubernetes_version_without_v_refused" {
  command = plan
  variables {
    kubernetes_version = "1.37.2"
  }
  expect_failures = [var.kubernetes_version]
}

run "kubernetes_version_without_patch_refused" {
  command = plan
  variables {
    kubernetes_version = "v1.37"
  }
  expect_failures = [var.kubernetes_version]
}

run "empty_installer_image_refused" {
  command = plan
  variables {
    installer_image = " "
  }
  expect_failures = [var.installer_image]
}

run "invalid_node_name_refused" {
  command = plan
  variables {
    nodes = {
      "CP_1" = { role = "controlplane", ip = "192.0.2.3" }
    }
  }
  expect_failures = [var.nodes]
}

run "invalid_node_role_refused" {
  command = plan
  variables {
    nodes = {
      "cp-1" = { role = "master", ip = "192.0.2.3" }
    }
  }
  expect_failures = [var.nodes]
}

run "no_control_plane_refused" {
  command = plan
  variables {
    nodes = {
      "worker-1" = { role = "worker", ip = "192.0.2.6" }
    }
  }
  expect_failures = [var.nodes]
}

run "two_control_planes_refused" {
  command = plan
  variables {
    nodes = {
      "cp-1" = { role = "controlplane", ip = "192.0.2.3" }
      "cp-2" = { role = "controlplane", ip = "192.0.2.4" }
    }
  }
  expect_failures = [var.nodes]
}

run "node_ip_with_prefix_refused" {
  command = plan
  variables {
    nodes = {
      "cp-1" = { role = "controlplane", ip = "192.0.2.3/27" }
    }
  }
  expect_failures = [var.nodes]
}

run "invalid_node_ip_refused" {
  command = plan
  variables {
    nodes = {
      "cp-1" = { role = "controlplane", ip = "192.0.2.999" }
    }
  }
  expect_failures = [var.nodes]
}

run "duplicate_node_ip_refused" {
  command = plan
  variables {
    nodes = {
      "cp-1"     = { role = "controlplane", ip = "192.0.2.3" }
      "worker-1" = { role = "worker", ip = "192.0.2.3" }
    }
  }
  expect_failures = [var.nodes]
}

run "ipv6_node_addresses_accepted" {
  command = plan
  variables {
    nodes = {
      "cp-1" = { role = "controlplane", ip = "2001:db8::3" }
    }
  }
}

run "invalid_network_cidr_refused" {
  command = plan
  variables {
    network = { cidr = "192.0.2.0", gateway = "192.0.2.1" }
  }
  expect_failures = [var.network]
}

run "invalid_network_gateway_refused" {
  command = plan
  variables {
    network = { cidr = "192.0.2.0/27", gateway = "gateway" }
  }
  expect_failures = [var.network]
}

run "invalid_virtual_ip_refused" {
  command = plan
  variables {
    network = { cidr = "192.0.2.0/27", gateway = "192.0.2.1", vip = "192.0.2.2/27" }
  }
  expect_failures = [var.network]
}

run "invalid_nameserver_refused" {
  command = plan
  variables {
    nameservers = ["dns.example.test"]
  }
  expect_failures = [var.nameservers]
}

run "invalid_node_subnet_refused" {
  command = plan
  variables {
    node_subnets = ["192.0.2.0"]
  }
  expect_failures = [var.node_subnets]
}

run "invalid_pod_subnet_refused" {
  command = plan
  variables {
    pod_subnets = ["10.244.0.0"]
  }
  expect_failures = [var.pod_subnets]
}

run "invalid_service_subnet_refused" {
  command = plan
  variables {
    service_subnets = ["not-a-cidr"]
  }
  expect_failures = [var.service_subnets]
}

run "invalid_cni_refused" {
  command = plan
  variables {
    cni = "calico"
  }
  expect_failures = [var.cni]
}

run "invalid_encryption_method_refused" {
  command = plan
  variables {
    encryption = { method = "static" }
  }
  expect_failures = [var.encryption]
}

run "oidc_with_plain_http_issuer_refused" {
  command = plan
  variables {
    oidc = { issuer_url = "http://dex.example.test", client_id = "kubernetes" }
  }
  expect_failures = [var.oidc]
}

run "oidc_with_empty_client_id_refused" {
  command = plan
  variables {
    oidc = { issuer_url = "https://dex.example.test", client_id = " " }
  }
  expect_failures = [var.oidc]
}

run "oidc_with_kubernetes_before_1_34_refused" {
  command = plan
  variables {
    kubernetes_version = "v1.33.9"
    oidc               = { issuer_url = "https://dex.example.test", client_id = "kubernetes" }
  }
  expect_failures = [var.oidc]
}

run "oidc_with_kubernetes_1_34_accepted" {
  command = plan
  variables {
    kubernetes_version = "v1.34.0"
    oidc               = { issuer_url = "https://dex.example.test", client_id = "kubernetes" }
  }
}

run "invalid_reboot_mode_refused" {
  command = plan
  variables {
    reboot_mode = "FAST"
  }
  expect_failures = [var.reboot_mode]
}
