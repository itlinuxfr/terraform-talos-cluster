# Tests without real machines: the Talos provider is replaced by a mock provider.
# `command = plan` creates nothing. The generated configuration is checked through the config_patches given to each node.

mock_provider "talos" {}

variables {
  cluster_name       = "demo"
  cluster_endpoint   = "https://192.0.2.2:6443"
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
      data.talos_machine_configuration.node["cp-1"].talos_version == "v1.14" &&
      talos_machine_secrets.this[0].talos_version == "v1.14" &&
      data.talos_machine_configuration.node["cp-1"].kubernetes_version == "v1.37.2" &&
      data.talos_machine_configuration.node["cp-1"].cluster_endpoint == "https://192.0.2.2:6443"
    )
    error_message = "The configuration of each node must carry its role, the contract version, the Kubernetes version and the endpoint."
  }
  assert {
    condition = (
      length(data.talos_machine_configuration.node["cp-1"].config_patches) == 0 &&
      length(data.talos_machine_configuration.node["worker-1"].config_patches) == 0
    )
    error_message = "Without options the module must leave the generated documents untouched."
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
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "UnattendedInstallConfig"][0].installer.image == "factory.example/installer:v1.14.6" &&
      [for p in data.talos_machine_configuration.node["cp-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "UnattendedInstallConfig"][0].provisioning.diskSelector.match == "disk.dev_path == \"/dev/sda\"" &&
      [for p in data.talos_machine_configuration.node["worker-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "UnattendedInstallConfig"][0].installer.image == "factory.example/installer-gpu:v1.14.6" &&
      [for p in data.talos_machine_configuration.node["worker-1"].config_patches : yamldecode(p) if try(yamldecode(p).kind, "") == "UnattendedInstallConfig"][0].provisioning.diskSelector.match == "disk.dev_path == \"/dev/nvme0n1\""
    )
    error_message = "The installation disk and image of each node must be written in its UnattendedInstallConfig."
  }
}

run "disk_encryption_with_tpm" {
  command = plan

  variables {
    encryption = {}
  }

  assert {
    condition = (
      length(data.talos_machine_configuration.node["cp-1"].config_patches) == 2 &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).kind == "VolumeConfig" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).name == "STATE" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).encryption.provider == "luks2" &&
      !can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).encryption.keys[0].lockToState) &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).encryption.keys[0].tpm == {}
    )
    error_message = "STATE must be encrypted with LUKS2 and a TPM key, without lockToState."
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).name == "EPHEMERAL" &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).encryption.keys[0].lockToState == true &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).encryption.keys[0].tpm == {}
    )
    error_message = "EPHEMERAL must be encrypted with a TPM key locked to STATE."
  }

  assert {
    condition     = length(data.talos_machine_configuration.node["worker-1"].config_patches) == 2
    error_message = "Workers must get the encryption patches too."
  }
}

run "disk_encryption_requires_secureboot" {
  command = plan

  variables {
    encryption = { tpm_require_secureboot = true }
  }

  assert {
    condition     = yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).encryption.keys[0].tpm.checkSecurebootStatusOnEnroll == true
    error_message = "tpm_require_secureboot must make the enrollment check SecureBoot, with the field next to options and not inside it."
  }

  assert {
    condition     = !can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).encryption.keys[0].tpm.options)
    error_message = "The Talos parser refuses checkSecurebootStatusOnEnroll inside tpm.options: the module must not write an options block for it."
  }
}

run "disk_encryption_with_node_id" {
  command = plan

  variables {
    encryption = { method = "node_id" }
  }

  assert {
    condition = (
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).encryption.keys[0].nodeID == {} &&
      !can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).encryption.keys[0].tpm)
    )
    error_message = "The node_id method must use a nodeID key and no TPM key."
  }
}


run "caller_patches_come_last_in_order" {
  command = plan

  variables {
    config_patches = {
      all          = ["apiVersion: v1alpha1\nkind: SysctlConfig\nparams:\n  vm.max_map_count: \"262144\"\n"]
      controlplane = ["cluster:\n  discovery:\n    enabled: false\n"]
      worker       = ["apiVersion: v1alpha1\nkind: KubeletConfig\nextraArgs:\n  max-pods: \"200\"\n"]
    }
    nodes = {
      "cp-1"     = { role = "controlplane", ip = "192.0.2.3", config_patches = ["apiVersion: v1alpha1\nkind: KubeNodeConfig\nannotations:\n  owner: me\n"] }
      "worker-1" = { role = "worker", ip = "192.0.2.6" }
    }
  }

  assert {
    condition = (
      length(data.talos_machine_configuration.node["cp-1"].config_patches) == 3 &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[0]).kind == "SysctlConfig" &&
      can(yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[1]).cluster.discovery) &&
      yamldecode(data.talos_machine_configuration.node["cp-1"].config_patches[2]).annotations == { owner = "me" }
    )
    error_message = "Order must be: module patches, patches for all nodes, patches for the role, patches of the node."
  }

  assert {
    condition = (
      length(data.talos_machine_configuration.node["worker-1"].config_patches) == 2 &&
      yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[0]).kind == "SysctlConfig" &&
      yamldecode(data.talos_machine_configuration.node["worker-1"].config_patches[1]).extraArgs == { "max-pods" = "200" }
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
