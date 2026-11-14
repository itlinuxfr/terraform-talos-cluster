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

  # ---------------------------------------------------------------------------------------------------------------
  # Patches for every node. Empty sections are left out, so the generated configuration stays as close as possible to the Talos default.
  # ---------------------------------------------------------------------------------------------------------------

  base_network = merge(
    var.cni == "none" ? { cni = { name = "none" } } : {},
    length(var.pod_subnets) > 0 ? { podSubnets = var.pod_subnets } : {},
    length(var.service_subnets) > 0 ? { serviceSubnets = var.service_subnets } : {},
  )

  base_cluster = merge(
    length(local.base_network) > 0 ? { network = local.base_network } : {},
    var.disable_kube_proxy ? { proxy = { disabled = true } } : {},
    var.allow_scheduling_on_control_planes ? { allowSchedulingOnControlPlanes = true } : {},
  )

  base_kubelet = merge(
    length(local.node_subnets) > 0 ? { nodeIP = { validSubnets = local.node_subnets } } : {},
    length(var.kubelet_extra_args) > 0 ? { extraArgs = var.kubelet_extra_args } : {},
  )

  base_machine = merge(
    length(var.nameservers) > 0 ? { network = { nameservers = var.nameservers } } : {},
    length(local.base_kubelet) > 0 ? { kubelet = local.base_kubelet } : {},
  )

  base_patch = yamlencode({ machine = local.base_machine, cluster = local.base_cluster })

  # ---------------------------------------------------------------------------------------------------------------
  # Patch for control planes: etcd and API server settings, OIDC, control plane metrics.
  # ---------------------------------------------------------------------------------------------------------------

  oidc_file_path = "/var/etc/kubernetes/authentication-config.yaml"

  # AuthenticationConfiguration v1 exists from Kubernetes 1.34 (checked in the oidc variable).
  oidc_config = var.oidc == null ? null : yamlencode({
    apiVersion = "apiserver.config.k8s.io/v1"
    kind       = "AuthenticationConfiguration"
    jwt = [{
      issuer = merge(
        { url = var.oidc.issuer_url, audiences = [var.oidc.client_id] },
        var.oidc.ca_certificate != null ? { certificateAuthority = var.oidc.ca_certificate } : {},
      )
      claimMappings = {
        username = { claim = var.oidc.username_claim, prefix = var.oidc.username_prefix }
        groups   = { claim = var.oidc.groups_claim, prefix = var.oidc.groups_prefix }
      }
    }]
  })

  etcd = merge(
    length(local.node_subnets) > 0 ? { advertisedSubnets = local.node_subnets } : {},
    var.expose_control_plane_metrics ? { extraArgs = { "listen-metrics-urls" = "http://0.0.0.0:2381" } } : {},
  )

  api_server_cert_sans = distinct(concat(var.api_server_cert_sans, var.network != null && var.network.vip != null ? [var.network.vip] : []))

  api_server = merge(
    length(local.api_server_cert_sans) > 0 ? { certSANs = local.api_server_cert_sans } : {},
    var.oidc != null ? { extraArgs = { "authentication-config" = local.oidc_file_path } } : {},
    var.oidc != null ? { extraVolumes = [{ hostPath = local.oidc_file_path, mountPath = local.oidc_file_path, readonly = true }] } : {},
  )

  metrics_bind_address = var.expose_control_plane_metrics ? { extraArgs = { "bind-address" = "0.0.0.0" } } : {}

  controlplane_cluster = {
    for section, settings in {
      etcd              = local.etcd
      apiServer         = local.api_server
      controllerManager = local.metrics_bind_address
      scheduler         = local.metrics_bind_address
    } : section => settings if length(settings) > 0
  }

  controlplane_machine = var.oidc != null ? {
    files = [{ path = local.oidc_file_path, permissions = 420, op = "create", content = local.oidc_config }]
  } : {}

  controlplane_patch = yamlencode({ machine = local.controlplane_machine, cluster = local.controlplane_cluster })

  # ---------------------------------------------------------------------------------------------------------------
  # Disk encryption (LUKS2). The key of STATE is sealed alone; the key of EPHEMERAL is also locked to the STATE salt.
  # ---------------------------------------------------------------------------------------------------------------

  encryption_method = var.encryption == null ? "" : var.encryption.method

  encryption_key = merge(
    local.encryption_method == "tpm" ? {
      tpm = try(var.encryption.tpm_require_secureboot, false) ? { options = { checkSecurebootStatusOnEnroll = true } } : {}
    } : {},
    local.encryption_method == "node_id" ? { nodeID = {} } : {},
  )

  encryption_patches = var.encryption == null ? [] : [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "VolumeConfig"
      name       = "STATE"
      encryption = { provider = "luks2", keys = [merge({ slot = 0 }, local.encryption_key)] }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "VolumeConfig"
      name       = "EPHEMERAL"
      encryption = { provider = "luks2", keys = [merge({ slot = 0, lockToState = true }, local.encryption_key)] }
    }),
  ]

  # ---------------------------------------------------------------------------------------------------------------
  # Patch of each node: installation, static network, labels and taints.
  # ---------------------------------------------------------------------------------------------------------------

  node_image = { for name, node in var.nodes : name => node.image != null ? node.image : var.installer_image }
  node_disk  = { for name, node in var.nodes : name => node.install_disk != null ? node.install_disk : var.install_disk }

  node_install = {
    for name, node in var.nodes : name => merge(
      local.node_disk[name] != null ? { disk = local.node_disk[name] } : {},
      local.node_image[name] != null ? { image = local.node_image[name] } : {},
    )
  }

  node_labels = { for name, node in var.nodes : name => merge(var.node_labels, node.labels) }

  node_patch = {
    for name, node in var.nodes : name => yamlencode({
      machine = merge(
        length(local.node_install[name]) > 0 ? { install = local.node_install[name] } : {},
        var.network != null ? {
          network = {
            interfaces = [merge(
              {
                deviceSelector = { physical = true }
                dhcp           = false
                addresses      = ["${node.ip}/${local.network_prefix}"]
                routes         = [{ network = strcontains(var.network.gateway, ":") ? "::/0" : "0.0.0.0/0", gateway = var.network.gateway }]
              },
              node.role == "controlplane" && var.network.vip != null ? { vip = { ip = var.network.vip } } : {},
            )]
          }
        } : {},
        length(local.node_labels[name]) > 0 ? { nodeLabels = local.node_labels[name] } : {},
        length(node.taints) > 0 ? { nodeTaints = node.taints } : {},
      )
    })
  }

  # Order matters: the module's patches first, then the caller's, so that the caller can override.
  node_patches = {
    for name, node in var.nodes : name => concat(
      [local.base_patch],
      node.role == "controlplane" ? [local.controlplane_patch] : [],
      local.encryption_patches,
      [local.node_patch[name]],
      var.config_patches.all,
      node.role == "controlplane" ? var.config_patches.controlplane : var.config_patches.worker,
      node.config_patches,
    )
  }
}

resource "talos_machine_secrets" "this" {
  count = local.external_secrets ? 0 : 1

  talos_version = var.talos_version
}

data "talos_machine_configuration" "node" {
  for_each = var.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = each.value.role
  machine_secrets    = local.machine_secrets
  talos_version      = var.talos_version
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
