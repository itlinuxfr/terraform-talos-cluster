# The configuration patches of each node, as Talos multi-document patches (Talos 1.14 and later).
#
# The Talos provider generates a document for most settings (UnattendedInstallConfig, ResolverConfig, KubeletConfig, KubeNodeConfig, KubeAPIServerConfig...).
# The module patches the generated document of the same kind (a patch is merged by kind and name). It never writes the deprecated v1alpha1 field of a setting
# that has a document: a node refuses the same setting in both formats. Field names come from the Talos sources (pkg/machinery/config/types).

locals {
  # The Talos configuration contract the module generates. It is NOT the installed Talos version (installer_image is): a later Talos release runs with this contract
  # until a release of the module moves it.
  talos_contract = "v1.14"

  doc_api_version = "v1alpha1"

  # The address plan of the primary network card. The alias gives it a stable name: the real name depends on the hypervisor (ens18, enp6s18...).
  doc_link_name = "net0"

  # ---------------------------------------------------------------------------------------------------------------
  # Documents for every node.
  # ---------------------------------------------------------------------------------------------------------------

  doc_base = concat(
    length(var.nameservers) > 0 ? [yamlencode({
      apiVersion  = local.doc_api_version
      kind        = "ResolverConfig"
      nameservers = [for address in var.nameservers : { address = address }]
    })] : [],
    length(var.kubelet_extra_args) > 0 ? [yamlencode({
      apiVersion = local.doc_api_version
      kind       = "KubeletConfig"
      extraArgs  = var.kubelet_extra_args
    })] : [],
    length(var.pod_subnets) + length(var.service_subnets) > 0 ? [yamlencode(merge(
      { apiVersion = local.doc_api_version, kind = "KubeNetworkConfig" },
      length(var.pod_subnets) > 0 ? { podSubnets = var.pod_subnets } : {},
      length(var.service_subnets) > 0 ? { serviceSubnets = var.service_subnets } : {},
    ))] : [],
  )

  # ---------------------------------------------------------------------------------------------------------------
  # Documents for control planes: kube-proxy and Flannel (Talos generates them on control planes only: a patch would create a worker document without an image), API server
  # certificate names, OIDC, control plane metrics. etcd has no document yet: its v1alpha1 fields stay.
  # ---------------------------------------------------------------------------------------------------------------

  doc_controlplane = concat(
    var.disable_kube_proxy ? [yamlencode({
      apiVersion = local.doc_api_version
      kind       = "KubeProxyConfig"
      enabled    = false
    })] : [],
    # Deleting the Flannel document disables the Flannel CNI (documented on KubeFlannelCNIConfig).
    var.cni == "none" ? ["apiVersion: ${local.doc_api_version}\nkind: KubeFlannelCNIConfig\n$patch: delete\n"] : [],
    length(local.api_server_cert_sans) > 0 ? [yamlencode({
      apiVersion    = local.doc_api_version
      kind          = "KubeAPIServerConfig"
      certExtraSANs = local.api_server_cert_sans
    })] : [],
    # The `configuration` field replaces the whole default (anonymous access to the health endpoints, no JWT issuer): keep the anonymous part.
    var.oidc != null ? [yamlencode({
      apiVersion = local.doc_api_version
      kind       = "KubeAuthenticationConfig"
      configuration = {
        anonymous = { enabled = true, conditions = [{ path = "/livez" }, { path = "/readyz" }, { path = "/healthz" }] }
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
      }
    })] : [],
    var.expose_control_plane_metrics ? [
      yamlencode({ apiVersion = local.doc_api_version, kind = "KubeControllerManagerConfig", extraArgs = { "bind-address" = "0.0.0.0" } }),
      yamlencode({ apiVersion = local.doc_api_version, kind = "KubeSchedulerConfig", extraArgs = { "bind-address" = "0.0.0.0" } }),
    ] : [],
    length(local.etcd) > 0 ? [yamlencode({ cluster = { etcd = local.etcd } })] : [],
  )

  # ---------------------------------------------------------------------------------------------------------------
  # Documents of each node: installation, static network, labels and taints.
  # ---------------------------------------------------------------------------------------------------------------

  doc_node = {
    for name, node in var.nodes : name => concat(
      length(local.node_install[name]) > 0 ? [yamlencode(merge(
        { apiVersion = local.doc_api_version, kind = "UnattendedInstallConfig" },
        local.node_image[name] != null ? { installer = { image = local.node_image[name] } } : {},
        local.node_disk[name] != null ? { provisioning = { diskSelector = { match = "disk.dev_path == ${jsonencode(local.node_disk[name])}" } } } : {},
      ))] : [],

      var.network != null ? concat(
        [
          yamlencode({
            apiVersion = local.doc_api_version
            kind       = "LinkAliasConfig"
            name       = local.doc_link_name
            # link.type is an enum: 1 is LINK_ETHER. With an empty kind it is a physical Ethernet card (the Physical() test of Talos).
            selector = { match = "link.type == 1 && link.kind == ''" }
          }),
          yamlencode({
            apiVersion = local.doc_api_version
            kind       = "LinkConfig"
            name       = local.doc_link_name
            addresses  = [{ address = "${node.ip}/${local.network_prefix}" }]
            # No destination: this is the default route (a node refuses 0.0.0.0/0 and ::/0 as an unspecified prefix).
            routes = [{ gateway = var.network.gateway }]
          }),
        ],
        node.role == "controlplane" && var.network.vip != null ? [yamlencode({
          apiVersion = local.doc_api_version
          kind       = "Layer2VIPConfig"
          name       = var.network.vip
          link       = local.doc_link_name
        })] : [],
      ) : [],

      # A control plane that runs workloads loses its NoSchedule taint. A merge patch cannot remove a key, so the generated document is deleted and
      # written again (the control-plane label stays; the exclude-from-external-load-balancers label is left out on purpose).
      node.role == "controlplane" && var.allow_scheduling_on_control_planes ? [
        "apiVersion: ${local.doc_api_version}\nkind: KubeNodeConfig\n$patch: delete\n",
      ] : [],
      length(local.node_subnets) + length(local.node_labels[name]) + length(node.taints) > 0 || (node.role == "controlplane" && var.allow_scheduling_on_control_planes) ? [yamlencode(merge(
        { apiVersion = local.doc_api_version, kind = "KubeNodeConfig" },
        length(local.node_subnets) > 0 ? { nodeIP = { validSubnets = local.node_subnets } } : {},
        { labels = merge(local.node_labels[name], node.role == "controlplane" && var.allow_scheduling_on_control_planes ? { "node-role.kubernetes.io/control-plane" = "" } : {}) },
        length(node.taints) > 0 ? { taints = node.taints } : {},
      ))] : [],
    )
  }

  # ---------------------------------------------------------------------------------------------------------------
  # Settings shared by the documents: etcd (no document yet: it stays in the v1alpha1 cluster.etcd section), API server names, installation, labels.
  # ---------------------------------------------------------------------------------------------------------------

  etcd = merge(
    length(local.node_subnets) > 0 ? { advertisedSubnets = local.node_subnets } : {},
    var.expose_control_plane_metrics ? { extraArgs = { "listen-metrics-urls" = "http://0.0.0.0:2381" } } : {},
  )

  api_server_cert_sans = distinct(concat(var.api_server_cert_sans, var.network != null && var.network.vip != null ? [var.network.vip] : []))

  # ---------------------------------------------------------------------------------------------------------------
  # Disk encryption (LUKS2). The key of STATE is sealed alone; the key of EPHEMERAL is also locked to the STATE salt.
  # ---------------------------------------------------------------------------------------------------------------

  encryption_method = var.encryption == null ? "" : var.encryption.method

  encryption_key = merge(
    local.encryption_method == "tpm" ? {
      # checkSecurebootStatusOnEnroll is a field of tpm itself, next to options (which only holds pcrs). Under options, the Talos parser refuses the document.
      tpm = try(var.encryption.tpm_require_secureboot, false) ? { checkSecurebootStatusOnEnroll = true } : {}
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

  node_image = { for name, node in var.nodes : name => node.image != null ? node.image : var.installer_image }
  node_disk  = { for name, node in var.nodes : name => node.install_disk != null ? node.install_disk : var.install_disk }

  node_install = {
    for name, node in var.nodes : name => merge(
      local.node_disk[name] != null ? { disk = local.node_disk[name] } : {},
      local.node_image[name] != null ? { image = local.node_image[name] } : {},
    )
  }

  node_labels = { for name, node in var.nodes : name => merge(var.node_labels, node.labels) }

  # Order matters: the module's patches first, then the caller's, so that the caller can override.
  node_patches = {
    for name, node in var.nodes : name => concat(
      local.doc_base,
      node.role == "controlplane" ? local.doc_controlplane : [],
      local.encryption_patches,
      local.doc_node[name],
      var.config_patches.all,
      node.role == "controlplane" ? var.config_patches.controlplane : var.config_patches.worker,
      node.config_patches,
    )
  }
}
