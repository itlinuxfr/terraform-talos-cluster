# The v1.14 contract: the module patches the generated documents (documents.tf) and writes no v1alpha1 field that the node would refuse next to them.
# The mock provider does not run the Talos parser: the real one is checked offline, then on a node (see AGENTS.md).

mock_provider "talos" {}

variables {
  cluster_name       = "demo"
  cluster_endpoint   = "https://192.0.2.2:6443"
  talos_version      = "v1.14"
  kubernetes_version = "v1.37.2"
  nodes = {
    "cp-1"     = { role = "controlplane", ip = "192.0.2.3" }
    "worker-1" = { role = "worker", ip = "192.0.2.6" }
  }
}

run "minimal_cluster_writes_no_patch" {
  command = plan

  assert {
    condition = (
      length(data.talos_machine_configuration.node["cp-1"].config_patches) == 0 &&
      length(data.talos_machine_configuration.node["worker-1"].config_patches) == 0
    )
    error_message = "Without options the v1.14 module must leave the generated documents untouched."
  }
}

run "every_option_writes_documents_and_no_conflicting_v1alpha1_field" {
  command = plan

  variables {
    installer_image              = "factory.talos.dev/installer/ID:v1.14.6"
    install_disk                 = "/dev/sda"
    network                      = { cidr = "192.0.2.0/27", gateway = "192.0.2.1", vip = "192.0.2.2" }
    nameservers                  = ["192.0.2.53"]
    pod_subnets                  = ["10.244.0.0/16"]
    service_subnets              = ["10.96.0.0/12"]
    node_labels                  = { "topology.kubernetes.io/region" = "lab" }
    kubelet_extra_args           = { "rotate-server-certificates" = "true" }
    disable_kube_proxy           = true
    cni                          = "none"
    api_server_cert_sans         = ["api.example.test"]
    expose_control_plane_metrics = true
    oidc                         = { issuer_url = "https://dex.example.test", client_id = "kubernetes" }
    encryption                   = { method = "tpm", tpm_require_secureboot = true }
  }

  # The only v1alpha1 documents left are the encryption volumes (VolumeConfig, a document too) and the etcd settings, which have no document yet.
  assert {
    condition = alltrue([
      for p in data.talos_machine_configuration.node["cp-1"].config_patches :
      !can(yamldecode(p).machine) && (!can(yamldecode(p).cluster) || keys(yamldecode(p).cluster) == ["etcd"])
    ])
    error_message = "No machine.* field and no cluster.* field except etcd may be written next to the generated documents."
  }

  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "ResolverConfig"][0].nameservers == [{ address = "192.0.2.53" }] &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeletConfig"][0].extraArgs == { "rotate-server-certificates" = "true" } &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeNetworkConfig"][0].podSubnets == ["10.244.0.0/16"] &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeNetworkConfig"][0].serviceSubnets == ["10.96.0.0/12"] &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeProxyConfig"][0].enabled == false
    )
    error_message = "DNS, kubelet arguments, subnets and kube-proxy must be written as documents."
  }

  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "UnattendedInstallConfig"][0].installer.image == "factory.talos.dev/installer/ID:v1.14.6" &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "UnattendedInstallConfig"][0].provisioning.diskSelector.match == "disk.dev_path == \"/dev/sda\""
    )
    error_message = "The installer image and the disk selector must be written in UnattendedInstallConfig."
  }

  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeNodeConfig"][0].nodeIP.validSubnets == ["192.0.2.0/27"] &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeNodeConfig"][0].labels == { "topology.kubernetes.io/region" = "lab" }
    )
    error_message = "The node IP subnets and the labels must be written in KubeNodeConfig."
  }

  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeAPIServerConfig"][0].certExtraSANs == ["api.example.test", "192.0.2.2"] &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeControllerManagerConfig"][0].extraArgs == { "bind-address" = "0.0.0.0" } &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeSchedulerConfig"][0].extraArgs == { "bind-address" = "0.0.0.0" }
    )
    error_message = "The API server names (the VIP included) and the control plane metrics must be written as documents."
  }

  assert {
    condition = (
      length([for p in data.talos_machine_configuration.node["cp-1"].config_patches : p if strcontains(p, "kind: KubeFlannelCNIConfig") && strcontains(p, "$patch: delete")]) == 1 &&
      length([for p in data.talos_machine_configuration.node["worker-1"].config_patches : p if strcontains(p, "KubeFlannelCNIConfig") || try(yamldecode(p).kind, "") == "KubeProxyConfig"]) == 0
    )
    error_message = "cni = none must delete the Flannel document on control planes, and workers get neither the Flannel nor the kube-proxy document."
  }
}

run "oidc_replaces_the_authentication_document_and_keeps_anonymous_health_checks" {
  command = plan

  variables {
    oidc = { issuer_url = "https://dex.example.test", client_id = "kubernetes", ca_certificate = "PEM" }
  }

  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeAuthenticationConfig"][0].configuration.jwt[0].issuer.url == "https://dex.example.test" &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeAuthenticationConfig"][0].configuration.jwt[0].issuer.certificateAuthority == "PEM" &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeAuthenticationConfig"][0].configuration.anonymous.enabled == true &&
      length([for p in data.talos_machine_configuration.node["cp-1"].config_patches : p if strcontains(p, "authentication-config")]) == 0
    )
    error_message = "OIDC must replace the authentication document, keep the anonymous health endpoints and write no file or API server argument."
  }

  assert {
    condition     = length(data.talos_machine_configuration.node["worker-1"].config_patches) == 0
    error_message = "A worker must not receive the OIDC document."
  }
}

run "static_network_writes_an_alias_a_link_and_a_virtual_ip_on_control_planes_only" {
  command = plan

  variables {
    network = { cidr = "192.0.2.0/27", gateway = "192.0.2.1", vip = "192.0.2.2" }
  }

  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "LinkAliasConfig"][0].name == "net0" &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "LinkAliasConfig"][0].selector.match == "link.kind == '' && link.type == 'ether'" &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "LinkConfig"][0].addresses == [{ address = "192.0.2.3/27" }] &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "LinkConfig"][0].routes == [{ destination = "0.0.0.0/0", gateway = "192.0.2.1" }] &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "Layer2VIPConfig"][0].name == "192.0.2.2" &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "Layer2VIPConfig"][0].link == "net0"
    )
    error_message = "A control plane needs the link alias, its static address and route, and the virtual IP on that link."
  }

  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["worker-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "LinkConfig"][0].addresses == [{ address = "192.0.2.6/27" }] &&
      length([for p in data.talos_machine_configuration.node["worker-1"].config_patches : p if try(yamldecode(p).kind, "") == "Layer2VIPConfig"]) == 0
    )
    error_message = "A worker gets its own address and never the virtual IP."
  }
}

run "ipv6_gateway_writes_an_ipv6_default_route" {
  command = plan

  variables {
    network = { cidr = "2001:db8::/64", gateway = "2001:db8::1" }
    nodes = {
      "cp-1" = { role = "controlplane", ip = "2001:db8::3" }
    }
  }

  assert {
    condition     = [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "LinkConfig"][0].routes == [{ destination = "::/0", gateway = "2001:db8::1" }]
    error_message = "An IPv6 gateway must give an IPv6 default route."
  }
}

run "control_plane_scheduling_deletes_and_rewrites_the_node_document_without_the_taint" {
  command = plan

  variables {
    allow_scheduling_on_control_planes = true
    node_labels                        = { "topology.kubernetes.io/region" = "lab" }
  }

  # A merge patch cannot remove the NoSchedule taint: the generated document is deleted, then written again.
  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p)
      if try(yamldecode(p).kind, "") == "KubeNodeConfig"][0]["$patch"] == "delete" &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p)
      if try(yamldecode(p).kind, "") == "KubeNodeConfig"][1].labels == { "node-role.kubernetes.io/control-plane" = "", "topology.kubernetes.io/region" = "lab" } &&
      !can([for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p)
      if try(yamldecode(p).kind, "") == "KubeNodeConfig"][1].taints)
    )
    error_message = "Scheduling on control planes must delete the generated node document and write it again with the control-plane label and no taint."
  }

  assert {
    condition     = length([for p in data.talos_machine_configuration.node["worker-1"].config_patches : p if strcontains(p, "$patch: delete")]) == 0
    error_message = "A worker must keep its generated node document."
  }
}

run "node_taints_and_labels_are_written_per_node" {
  command = plan

  variables {
    nodes = {
      "cp-1"     = { role = "controlplane", ip = "192.0.2.3", labels = { zone = "a" } }
      "worker-1" = { role = "worker", ip = "192.0.2.6", labels = { zone = "b" }, taints = { dedicated = "gpu:NoSchedule" } }
    }
  }

  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["worker-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeNodeConfig"][0].labels == { zone = "b" } &&
      [for p in data.talos_machine_configuration.node["worker-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeNodeConfig"][0].taints == { dedicated = "gpu:NoSchedule" } &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "KubeNodeConfig"][0].labels == { zone = "a" }
    )
    error_message = "Each node must carry its own labels and taints."
  }
}

run "etcd_settings_stay_in_the_v1alpha1_cluster_section" {
  command = plan

  variables {
    network                      = { cidr = "192.0.2.0/27", gateway = "192.0.2.1" }
    expose_control_plane_metrics = true
  }

  assert {
    condition = (
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p).cluster.etcd if can(yamldecode(p).cluster.etcd)][0] ==
      { advertisedSubnets = ["192.0.2.0/27"], extraArgs = { "listen-metrics-urls" = "http://0.0.0.0:2381" } }
    )
    error_message = "etcd has no document in Talos 1.14: its settings stay in the v1alpha1 cluster.etcd section."
  }
}

run "caller_patches_come_after_the_module_documents" {
  command = plan

  variables {
    nameservers = ["192.0.2.53"]
    config_patches = {
      all = ["apiVersion: v1alpha1\nkind: ResolverConfig\nnameservers:\n  - address: 192.0.2.99\n"]
    }
  }

  assert {
    condition = (
      length(data.talos_machine_configuration.node["cp-1"].config_patches) == 2 &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).nameservers[0].address == "192.0.2.99"
    )
    error_message = "The caller's patches must come last, so that they override the module's."
  }
}
