# Generate a set of secrets for the cluster

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "control_plane" {
  cluster_name     = var.talos_cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${var.talos_vip}:${var.talos_api_port}"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.talos_cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${var.talos_vip}:${var.talos_api_port}"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes = distinct(concat(
    [for k, v in var.talos_controlplanes : v.ip],
    [for k, v in var.talos_workernodes : v.ip]
  ))
}

locals {
  # Common configuration for all nodes
  common_config_patch = {
    cluster = {
      allowSchedulingOnControlPlanes = false
      network = {
        cni = {
          name = var.talos_cni
        }
        dnsDomain      = var.cluster_dns_domain
        podSubnets     = var.cluster_pod_subnets
        serviceSubnets = var.cluster_service_subnets
      }
      inlineManifests = var.talos_inline_manifests
    }
    machine = {
      install = {
        extraKernelArgs = var.talos_kernel_args
      }
      kubelet = {
        extraArgs = {
          "rotate-server-certificates" = true
        }
      }
    }
  }
}

resource "talos_machine_configuration_apply" "control_plane" {
  for_each                    = var.talos_controlplanes
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane.machine_configuration
  node                        = each.value.ip
  config_patches = [
    yamlencode(local.common_config_patch),
    yamlencode({
      machine = {
        install = {
          disk = each.value.disk
        }
        network = {
          interfaces = [
            {
              interface = each.value.interface
              dhcp      = false
              vip = {
                ip = var.talos_vip
              }
            }
          ]
          hostname = each.value.hostname
        }
        nodeLabels = each.value.node_labels
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each                    = var.talos_workernodes
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip
  config_patches = [
    yamlencode(local.common_config_patch),
    yamlencode({
      machine = {
        install = {
          disk = each.value.disk
        }
        network = {
          interfaces = [
            {
              interface = each.value.interface
              dhcp      = false
            }
          ]
          hostname = each.value.hostname
        }
        nodeLabels = merge(
          { "node-role.kubernetes.io/worker" = "" },
          each.value.node_labels
        )
      }
    })
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.control_plane
  ]
  # We need to pick one controlplane node to bootstrap.
  # Using values(var.talos_controlplanes)[0].ip assumes at least one CP exists.
  node                 = values(var.talos_controlplanes)[0].ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

resource "talos_cluster_kubeconfig" "cluster" {
  depends_on = [
    talos_machine_bootstrap.this
  ]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = values(var.talos_controlplanes)[0].ip
}
