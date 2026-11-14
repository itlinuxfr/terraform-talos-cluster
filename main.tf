# Builds a Talos Linux cluster on machines that already exist and boot Talos: it generates the secrets and the machine configuration of each node,
# applies it, bootstraps etcd and returns the kubeconfig and the talosconfig. Creating the machines and the Talos image is not its job.
#
# Order: control planes, then talos_cluster (etcd bootstrap and Kubernetes upgrades), then workers.
# For an OS upgrade or a configuration change that restarts nodes, run `terraform apply -parallelism=1`: talos_machine waits for each node
# to be ready again, so the nodes restart one after the other and etcd keeps its quorum.

locals {
  controlplanes = { for name, node in var.nodes : name => node if node.role == "controlplane" }
  workers       = { for name, node in var.nodes : name => node if node.role == "worker" }

  # The first control plane by name bootstraps etcd and serves the kubeconfig (keys() returns the names in lexical order).
  controlplane_ips      = [for name in keys(local.controlplanes) : local.controlplanes[name].ip]
  first_controlplane_ip = local.controlplane_ips[0]

  # The value is sensitive, but whether it is set is not a secret.
  external_secrets = nonsensitive(var.secrets != null)

  machine_secrets      = local.external_secrets ? var.secrets.machine_secrets : talos_machine_secrets.this[0].machine_secrets
  client_configuration = local.external_secrets ? var.secrets.client_configuration : talos_machine_secrets.this[0].client_configuration

  network_prefix = var.network != null ? tonumber(split("/", var.network.cidr)[1]) : null
  node_subnets   = length(var.node_subnets) > 0 ? var.node_subnets : (var.network != null ? [var.network.cidr] : [])
}

resource "talos_machine_secrets" "this" {
  count = local.external_secrets ? 0 : 1

  talos_version = local.talos_contract
}

data "talos_machine_configuration" "node" {
  for_each = var.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = each.value.role
  machine_secrets    = local.machine_secrets
  talos_version      = local.talos_contract
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches     = local.node_patches[each.key]
}

# Applies the configuration, waits for the node to be ready and, when an image is set, keeps the Talos version in sync.
# Applying always uses the AUTO mode: a change that needs a restart restarts the node at once, without drain.
resource "talos_machine" "controlplane" {
  for_each = local.controlplanes

  node                            = each.value.ip
  client_configuration            = local.client_configuration
  machine_configuration           = data.talos_machine_configuration.node[each.key].machine_configuration
  image                           = local.node_image[each.key]
  drain_on_upgrade                = var.drain_on_upgrade
  kubeconfig_wo                   = var.kubeconfig
  reboot_mode                     = var.reboot_mode
  ignore_kubernetes_upgrade_drift = var.ignore_kubernetes_upgrade_drift
}

# Bootstraps etcd on the first control plane, waits for the Talos layer to be healthy on all control planes,
# and upgrades Kubernetes when kubernetes_version changes. It does not wait for Kubernetes components: with cni = none, nodes stay NotReady
# until the CNI is installed.
resource "talos_cluster" "this" {
  node                 = local.first_controlplane_ip
  control_plane_nodes  = local.controlplane_ips
  client_configuration = local.client_configuration
  kubernetes_version   = var.kubernetes_version

  depends_on = [talos_machine.controlplane]
}

# Workers come after the cluster: an upgrade then always reaches the control planes first.
resource "talos_machine" "worker" {
  for_each = local.workers

  node                            = each.value.ip
  client_configuration            = local.client_configuration
  machine_configuration           = data.talos_machine_configuration.node[each.key].machine_configuration
  image                           = local.node_image[each.key]
  drain_on_upgrade                = var.drain_on_upgrade
  kubeconfig_wo                   = var.kubeconfig
  reboot_mode                     = var.reboot_mode
  ignore_kubernetes_upgrade_drift = var.ignore_kubernetes_upgrade_drift

  depends_on = [talos_cluster.this]
}

resource "talos_cluster_kubeconfig" "this" {
  node                 = local.first_controlplane_ip
  client_configuration = local.client_configuration

  depends_on = [talos_cluster.this]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = local.client_configuration
  endpoints            = local.controlplane_ips # never the virtual IP: talosctl must reach each node
  nodes                = [for name in keys(var.nodes) : var.nodes[name].ip]
}
