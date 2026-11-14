# Configuration for the v1.14 contract and later: multi-document patches instead of the deprecated v1alpha1 fields.
#
# From the v1.14 contract the Talos provider generates a document for most settings (UnattendedInstallConfig, ResolverConfig, KubeletConfig, KubeNodeConfig,
# KubeAPIServerConfig...). A node refuses the same setting in both formats, so for these contracts the module patches the generated document of the same kind
# (a patch is merged by kind and name) and writes no v1alpha1 field for it. For the v1.13 contract and earlier, main.tf writes the v1alpha1 patches.
# Field names come from the Talos v1.14 sources (pkg/machinery/config/types).

locals {
  contract_minor = can(regex("^v?[0-9]+\\.([0-9]+)", var.talos_version)) ? tonumber(regex("^v?[0-9]+\\.([0-9]+)", var.talos_version)[0]) : 0
  multidoc       = local.contract_minor >= 14

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
            selector   = { match = "link.kind == '' && link.type == 'ether'" }
          }),
          yamlencode({
            apiVersion = local.doc_api_version
            kind       = "LinkConfig"
            name       = local.doc_link_name
            addresses  = [{ address = "${node.ip}/${local.network_prefix}" }]
            routes = [{
              destination = strcontains(var.network.gateway, ":") ? "::/0" : "0.0.0.0/0"
              gateway     = var.network.gateway
            }]
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
}
