# Tests without real machines: the Talos provider is replaced by a mock provider.
# `command = plan` creates nothing. The generated configuration is checked through the config_patches given to each node.

mock_provider "talos" {}

variables {
  cluster_name       = "demo"
  cluster_endpoint   = "https://192.0.2.2:6443"
  talos_version      = "v1.13"
  kubernetes_version = "v1.37.2"
  nodes = {
    "cp-1"     = { role = "controlplane", ip = "192.0.2.3" }
    "cp-2"     = { role = "controlplane", ip = "192.0.2.4" }
    "cp-3"     = { role = "controlplane", ip = "192.0.2.5" }
    "worker-1" = { role = "worker", ip = "192.0.2.6" }
  }
}

run "minimal_cluster_stays_close_to_the_talos_default" {
  command = plan

  assert {
    condition     = length(talos_machine.controlplane) == 3 && length(talos_machine.worker) == 1 && length(talos_machine_secrets.this) == 1
    error_message = "Three control planes, one worker and generated secrets are expected."
  }

  assert {
    condition = (
      talos_cluster.this.node == "192.0.2.3" &&
      talos_cluster.this.control_plane_nodes == tolist(["192.0.2.3", "192.0.2.4", "192.0.2.5"]) &&
      talos_cluster.this.kubernetes_version == "v1.37.2"
    )
    error_message = "etcd must bootstrap on the first control plane in alphabetical order, with all control planes checked."
  }

  assert {
    condition = (
      data.talos_machine_configuration.node["cp-1"].machine_type == "controlplane" &&
      data.talos_machine_configuration.node["worker-1"].machine_type == "worker" &&
      data.talos_machine_configuration.node["cp-1"].talos_version == "v1.13" &&
      data.talos_machine_configuration.node["cp-1"].kubernetes_version == "v1.37.2" &&
      data.talos_machine_configuration.node["cp-1"].cluster_endpoint == "https://192.0.2.2:6443"
    )
    error_message = "The configuration of each node must carry its role, the contract version, the Kubernetes version and the endpoint."
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]) == { machine = {}, cluster = {} } &&
      length(data.talos_machine_configuration.node["cp-1"].config_patches) == 3 &&
      length(data.talos_machine_configuration.node["worker-1"].config_patches) == 2
    )
    error_message = "Without options the module patches must be empty: base, control plane and node for a control plane, base and node for a worker."
  }

  assert {
    # The image is not asserted: when unset, the provider computes it, so it is unknown at plan time.
    condition = (
      talos_machine.controlplane["cp-1"].drain_on_upgrade == false &&
      talos_machine.controlplane["cp-1"].ignore_kubernetes_upgrade_drift == true
    )
    error_message = "By default nothing is drained and Kubernetes upgrades are left to talos_cluster."
  }
}

run "cni_none_without_kube_proxy" {
  command = plan

  variables {
    cni                                = "none"
    disable_kube_proxy                 = true
    allow_scheduling_on_control_planes = true
    pod_subnets                        = ["10.244.0.0/16"]
    service_subnets                    = ["10.96.0.0/12"]
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).cluster.network.cni.name == "none" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).cluster.proxy.disabled == true &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).cluster.allowSchedulingOnControlPlanes == true
    )
    error_message = "cni none, no kube-proxy and scheduling on control planes must be written in the cluster section."
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).cluster.network.podSubnets == ["10.244.0.0/16"] &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).cluster.network.serviceSubnets == ["10.96.0.0/12"]
    )
    error_message = "Pod and service subnets must be written."
  }
}

run "static_network_and_virtual_ip" {
  command = plan

  variables {
    network = { cidr = "192.0.2.0/27", gateway = "192.0.2.1", vip = "192.0.2.2" }
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).machine.kubelet.nodeIP.validSubnets == ["192.0.2.0/27"] &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).cluster.etcd.advertisedSubnets == ["192.0.2.0/27"] &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).cluster.apiServer.certSANs == ["192.0.2.2"]
    )
    error_message = "The network cidr must become the node subnet of kubelet and etcd, and the virtual IP must be an API server SAN."
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).machine.network.interfaces[0].addresses == ["192.0.2.3/27"] &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).machine.network.interfaces[0].dhcp == false &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).machine.network.interfaces[0].routes[0].gateway == "192.0.2.1" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).machine.network.interfaces[0].vip.ip == "192.0.2.2"
    )
    error_message = "A control plane must get its static address, the default route and the virtual IP."
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[1]).machine.network.interfaces[0].addresses == ["192.0.2.6/27"] &&
      !can(yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[1]).machine.network.interfaces[0].vip)
    )
    error_message = "A worker must get its static address and no virtual IP."
  }
}

run "nameservers_and_kubelet_arguments" {
  command = plan

  variables {
    nameservers        = ["192.0.2.53"]
    node_subnets       = ["192.0.2.0/27"]
    kubelet_extra_args = { "rotate-server-certificates" = "true" }
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[0]).machine.network.nameservers == ["192.0.2.53"] &&
      yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[0]).machine.kubelet.extraArgs["rotate-server-certificates"] == "true" &&
      yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[0]).machine.kubelet.nodeIP.validSubnets == ["192.0.2.0/27"]
    )
    error_message = "Nameservers, kubelet arguments and node subnets must be written for every node."
  }
}

run "labels_and_taints" {
  command = plan

  variables {
    node_labels = { "topology.kubernetes.io/region" = "lab", "tier" = "default" }
    nodes = {
      "cp-1" = { role = "controlplane", ip = "192.0.2.3" }
      "worker-1" = {
        role   = "worker"
        ip     = "192.0.2.6"
        labels = { "tier" = "storage", "topology.kubernetes.io/zone" = "pve-01" }
        taints = { "dedicated" = "storage:NoSchedule" }
      }
    }
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[1]).machine.nodeLabels == {
        "topology.kubernetes.io/region" = "lab"
        "tier"                          = "storage"
        "topology.kubernetes.io/zone"   = "pve-01"
      } &&
      yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[1]).machine.nodeTaints == { "dedicated" = "storage:NoSchedule" }
    )
    error_message = "Node labels must win over cluster labels, and taints must be written."
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).machine.nodeLabels == { "topology.kubernetes.io/region" = "lab", "tier" = "default" } &&
      !can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).machine.nodeTaints)
    )
    error_message = "A node without its own labels must get the cluster labels, and no taint."
  }
}

run "installer_image_and_install_disk_with_overrides" {
  command = plan

  variables {
    installer_image = "factory.example/installer:v1.14.6"
    install_disk    = "/dev/sda"
    nodes = {
      "cp-1" = { role = "controlplane", ip = "192.0.2.3" }
      "worker-1" = {
        role         = "worker"
        ip           = "192.0.2.6"
        install_disk = "/dev/nvme0n1"
        image        = "factory.example/installer-gpu:v1.14.6"
      }
    }
  }

  assert {
    condition = (
      talos_machine.controlplane["cp-1"].image == "factory.example/installer:v1.14.6" &&
      talos_machine.worker["worker-1"].image == "factory.example/installer-gpu:v1.14.6"
    )
    error_message = "A node image must win over the cluster image, and the image must reach talos_machine."
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).machine.install == { disk = "/dev/sda", image = "factory.example/installer:v1.14.6" } &&
      yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[1]).machine.install == { disk = "/dev/nvme0n1", image = "factory.example/installer-gpu:v1.14.6" }
    )
    error_message = "The installation disk and image of each node must be written in its patch."
  }
}

run "disk_encryption_with_tpm" {
  command = plan

  variables {
    encryption = {}
  }

  assert {
    condition = (
      length(data.talos_machine_configuration.node["cp-1"].config_patches) == 5 &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).kind == "VolumeConfig" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).name == "STATE" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).encryption.provider == "luks2" &&
      !can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).encryption.keys[0].lockToState) &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).encryption.keys[0].tpm == {}
    )
    error_message = "STATE must be encrypted with LUKS2 and a TPM key, without lockToState."
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[3]).name == "EPHEMERAL" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[3]).encryption.keys[0].lockToState == true &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[3]).encryption.keys[0].tpm == {}
    )
    error_message = "EPHEMERAL must be encrypted with a TPM key locked to STATE."
  }

  assert {
    condition     = length(data.talos_machine_configuration.node["worker-1"].config_patches) == 4
    error_message = "Workers must get the encryption patches too."
  }
}

run "disk_encryption_requires_secureboot" {
  command = plan

  variables {
    encryption = { tpm_require_secureboot = true }
  }

  assert {
    condition     = yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).encryption.keys[0].tpm.options.checkSecurebootStatusOnEnroll == true
    error_message = "tpm_require_secureboot must make the enrollment check SecureBoot."
  }
}

run "disk_encryption_with_node_id" {
  command = plan

  variables {
    encryption = { method = "node_id" }
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).encryption.keys[0].nodeID == {} &&
      !can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).encryption.keys[0].tpm)
    )
    error_message = "The node_id method must use a nodeID key and no TPM key."
  }
}

run "oidc_authentication" {
  command = plan

  variables {
    oidc = {
      issuer_url     = "https://dex.example.test"
      client_id      = "kubernetes"
      ca_certificate = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"
    }
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).machine.files[0].path == "/var/etc/kubernetes/authentication-config.yaml" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).machine.files[0].op == "create" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).cluster.apiServer.extraArgs["authentication-config"] == "/var/etc/kubernetes/authentication-config.yaml" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).cluster.apiServer.extraVolumes[0].readonly == true
    )
    error_message = "The OIDC file, the API server argument and the volume must be written for control planes."
  }

  assert {
    condition = (
      yamldecode(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).machine.files[0].content).apiVersion == "apiserver.config.k8s.io/v1" &&
      yamldecode(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).machine.files[0].content).jwt[0].issuer.url == "https://dex.example.test" &&
      yamldecode(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).machine.files[0].content).jwt[0].issuer.audiences == ["kubernetes"] &&
      yamldecode(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).machine.files[0].content).jwt[0].claimMappings.username == { claim = "email", prefix = "oidc:" } &&
      yamldecode(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).machine.files[0].content).jwt[0].claimMappings.groups == { claim = "groups", prefix = "oidc:" }
    )
    error_message = "The AuthenticationConfiguration must carry the issuer, the audience and the default claim mappings."
  }

  assert {
    condition     = yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[1]) == { machine = {} }
    error_message = "Workers must not get the OIDC file."
  }
}

run "oidc_without_certificate_authority" {
  command = plan

  variables {
    oidc = { issuer_url = "https://dex.example.test", client_id = "kubernetes" }
  }

  assert {
    condition     = !can(yamldecode(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).machine.files[0].content).jwt[0].issuer.certificateAuthority)
    error_message = "Without ca_certificate the issuer must not carry a certificateAuthority."
  }
}

run "control_plane_metrics_exposed" {
  command = plan

  variables {
    expose_control_plane_metrics = true
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).cluster.etcd.extraArgs["listen-metrics-urls"] == "http://0.0.0.0:2381" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).cluster.controllerManager.extraArgs["bind-address"] == "0.0.0.0" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).cluster.scheduler.extraArgs["bind-address"] == "0.0.0.0"
    )
    error_message = "etcd, kube-controller-manager and kube-scheduler metrics must be exposed on control planes."
  }
}

run "caller_patches_come_last_in_order" {
  command = plan

  variables {
    config_patches = {
      all          = ["machine:\n  sysctls:\n    vm.max_map_count: \"262144\"\n"]
      controlplane = ["cluster:\n  discovery:\n    enabled: false\n"]
      worker       = ["machine:\n  kubelet:\n    extraConfig:\n      maxPods: 200\n"]
    }
    nodes = {
      "cp-1"     = { role = "controlplane", ip = "192.0.2.3", config_patches = ["machine:\n  nodeAnnotations:\n    owner: me\n"] }
      "worker-1" = { role = "worker", ip = "192.0.2.6" }
    }
  }

  assert {
    condition = (
      length(data.talos_machine_configuration.node["cp-1"].config_patches) == 6 &&
      can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[3]).machine.sysctls) &&
      can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[4]).cluster.discovery) &&
      can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[5]).machine.nodeAnnotations)
    )
    error_message = "Order must be: module patches, patches for all nodes, patches for the role, patches of the node."
  }

  assert {
    condition = (
      length(data.talos_machine_configuration.node["worker-1"].config_patches) == 4 &&
      can(yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[2]).machine.sysctls) &&
      can(yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[3]).machine.kubelet.extraConfig)
    )
    error_message = "A worker must get the patches for all nodes and the worker patches, not the control plane ones."
  }
}

run "external_secrets_are_used_instead_of_generated" {
  command = plan

  variables {
    secrets = {
      # The complete structure of the provider machine_secrets, with dummy values.
      machine_secrets = {
        certs = {
          etcd               = { cert = "c", key = "k" }
          k8s                = { cert = "c", key = "k" }
          k8s_aggregator     = { cert = "c", key = "k" }
          k8s_serviceaccount = { key = "k" }
          os                 = { cert = "c", key = "k" }
        }
        cluster = { id = "external-id", secret = "external-secret" }
        secrets = {
          aescbc_encryption_secret    = "a"
          bootstrap_token             = "b"
          secretbox_encryption_secret = "s"
        }
        trustdinfo = { token = "t" }
      }
      client_configuration = {
        ca_certificate     = "ca"
        client_certificate = "cert"
        client_key         = "key"
      }
    }
  }

  assert {
    condition     = length(talos_machine_secrets.this) == 0
    error_message = "The module must not generate secrets when they are provided."
  }

  assert {
    condition     = data.talos_machine_configuration.node["cp-1"].machine_secrets.cluster.id == "external-id"
    error_message = "The provided machine secrets must feed the machine configuration."
  }
}

run "os_upgrade_options_reach_talos_machine" {
  command = plan

  variables {
    installer_image                 = "factory.example/installer:v1.14.6"
    drain_on_upgrade                = true
    kubeconfig                      = "kubeconfig-for-test"
    reboot_mode                     = "POWERCYCLE"
    ignore_kubernetes_upgrade_drift = false
  }

  assert {
    condition = (
      talos_machine.controlplane["cp-1"].drain_on_upgrade == true &&
      talos_machine.worker["worker-1"].drain_on_upgrade == true &&
      talos_machine.controlplane["cp-1"].reboot_mode == "POWERCYCLE" &&
      talos_machine.worker["worker-1"].ignore_kubernetes_upgrade_drift == false
    )
    error_message = "drain_on_upgrade, reboot_mode and ignore_kubernetes_upgrade_drift must reach every talos_machine."
  }
}

run "single_node_cluster" {
  command = plan

  variables {
    allow_scheduling_on_control_planes = true
    nodes = {
      "solo" = { role = "controlplane", ip = "192.0.2.3" }
    }
  }

  assert {
    condition     = length(talos_machine.controlplane) == 1 && length(talos_machine.worker) == 0 && talos_cluster.this.node == "192.0.2.3"
    error_message = "A single control plane without workers must work."
  }
}

run "five_control_planes_bootstrap_on_the_first_in_name_order" {
  command = plan

  variables {
    nodes = {
      "cp-e" = { role = "controlplane", ip = "192.0.2.15" }
      "cp-d" = { role = "controlplane", ip = "192.0.2.14" }
      "cp-c" = { role = "controlplane", ip = "192.0.2.13" }
      "cp-b" = { role = "controlplane", ip = "192.0.2.12" }
      "cp-a" = { role = "controlplane", ip = "192.0.2.11" }
    }
  }

  assert {
    condition     = talos_cluster.this.node == "192.0.2.11" && talos_cluster.this.control_plane_nodes == tolist(["192.0.2.11", "192.0.2.12", "192.0.2.13", "192.0.2.14", "192.0.2.15"])
    error_message = "The bootstrap node and the control plane list must follow the alphabetical order of node names, whatever the map order."
  }
}
