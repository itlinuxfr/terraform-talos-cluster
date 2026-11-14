variable "cluster_name" {
  description = "Name of the cluster. It ends up in the talosconfig and in the kubeconfig."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.cluster_name))
    error_message = "The cluster name must use lowercase letters, digits and hyphens, 63 characters at most, no hyphen at the start or the end."
  }
}

variable "cluster_endpoint" {
  description = "URL of the Kubernetes API that nodes and clients use, for example https://192.0.2.2:6443. With several control planes, use a virtual IP or a load balancer, never a single node."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^https://[^[:space:]]+$", var.cluster_endpoint))
    error_message = "The cluster endpoint must be an https:// URL without spaces."
  }
}

variable "talos_version" {
  description = "Talos version contract used to generate the machine configuration and the secrets, for example v1.14. It is NOT the installed Talos version (that is installer_image): a node on Talos 1.14 runs fine with the v1.13 contract, which writes the older v1alpha1 format. Pin it to the version the cluster was created with and do not raise it at each OS upgrade: raising it changes the generated configuration. v1.13 and v1.14 are supported (the v1.14 contract makes the module write the new multi-document format); later contracts are refused until the module is checked against them."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.talos_version))
    error_message = "The Talos version must look like v1.14 or v1.14.6."
  }

  # The module writes the v1alpha1 format up to the v1.13 contract and the document format for v1.14 (documents.tf). A later contract may generate more documents,
  # and a node refuses a setting that is written in both formats: refuse it here, with a clear message, until the module is checked against that Talos release.
  validation {
    condition     = !can(regex("^v?[0-9]+\\.[0-9]+", var.talos_version)) || tonumber(regex("^v?[0-9]+\\.([0-9]+)", var.talos_version)[0]) <= 14
    error_message = "The module is checked against the Talos v1.13 and v1.14 contracts. A later contract can generate documents that conflict with the module's patches, which a node refuses: use v1.14 until the module supports the new release."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version of the cluster, for example v1.37.2. Always set it: the provider default can be newer than the version you tested. Changing it runs the Talos upgrade-k8s procedure on a running cluster."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "The Kubernetes version must look like v1.37.2."
  }
}

variable "installer_image" {
  description = "Talos installer image, for example from the installer_image output of terraform-talos-image. When set, Terraform also manages the Talos version: changing it upgrades the nodes. Null leaves the installed version alone. A node can override it."
  type        = string
  default     = null

  validation {
    condition     = var.installer_image == null ? true : trimspace(var.installer_image) != ""
    error_message = "The installer image must not be empty."
  }
}

variable "install_disk" {
  description = "Disk that Talos installs on, for example /dev/sda. Null keeps the Talos default. A node can override it."
  type        = string
  default     = null
}

variable "nodes" {
  description = <<-EOT
    Nodes, keyed by name. The name is the Kubernetes node name when the machine takes its hostname from the platform.
    - role: controlplane or worker. The number of control planes must be odd (etcd quorum).
    - ip: IP address of the node, reachable by Terraform on the Talos API (port 50000).
    - install_disk, image: override the cluster-wide values.
    - labels, taints: Kubernetes node labels and taints (a taint value is "value:effect", for example "dedicated:NoSchedule").
    - config_patches: extra YAML patches for this node only.
  EOT
  type = map(object({
    role           = string
    ip             = string
    install_disk   = optional(string)
    image          = optional(string)
    labels         = optional(map(string), {})
    taints         = optional(map(string), {})
    config_patches = optional(list(string), [])
  }))
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.nodes) : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name))])
    error_message = "Node names must be hostname labels: lowercase letters, digits and hyphens, 63 characters at most."
  }

  validation {
    condition     = alltrue([for node in values(var.nodes) : contains(["controlplane", "worker"], node.role)])
    error_message = "A node role must be controlplane or worker."
  }

  validation {
    condition     = length([for node in values(var.nodes) : node if node.role == "controlplane"]) >= 1
    error_message = "At least one control plane node is required."
  }

  validation {
    condition     = length([for node in values(var.nodes) : node if node.role == "controlplane"]) % 2 == 1
    error_message = "The number of control plane nodes must be odd (1, 3, 5): an even number gives no more fault tolerance and risks losing the etcd quorum."
  }

  validation {
    condition     = alltrue([for node in values(var.nodes) : can(cidrhost("${node.ip}/${strcontains(node.ip, ":") ? 128 : 32}", 0))])
    error_message = "Every node ip must be an IPv4 or IPv6 address without a prefix length."
  }

  validation {
    condition     = length(distinct([for node in values(var.nodes) : node.ip])) == length(var.nodes)
    error_message = "Node IP addresses must be unique."
  }
}

variable "network" {
  description = <<-EOT
    Static network of the nodes. Null leaves the network to the platform (DHCP or cloud-init).
    - cidr: network of the nodes, for example 192.0.2.0/27.
    - gateway: default gateway.
    - vip: Talos virtual IP shared by the control planes, which should match the host of cluster_endpoint. Null adds none.
    The module sets a static address on the first physical interface of each node and the vip on control planes.
  EOT
  type = object({
    cidr    = string
    gateway = string
    vip     = optional(string)
  })
  default = null

  validation {
    condition     = var.network == null ? true : can(cidrhost(var.network.cidr, 0))
    error_message = "network.cidr must be a CIDR such as 192.0.2.0/27."
  }

  validation {
    condition = var.network == null ? true : (
      can(cidrhost("${var.network.gateway}/${strcontains(var.network.gateway, ":") ? 128 : 32}", 0)) &&
      (var.network.vip == null ? true : can(cidrhost("${var.network.vip}/${strcontains(var.network.vip, ":") ? 128 : 32}", 0)))
    )
    error_message = "network.gateway and network.vip must be IP addresses without a prefix length."
  }
}

variable "nameservers" {
  description = "DNS servers of the nodes. Empty keeps the ones from the platform."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for server in var.nameservers : can(cidrhost("${server}/${strcontains(server, ":") ? 128 : 32}", 0))])
    error_message = "Nameservers must be IP addresses."
  }
}

variable "node_subnets" {
  description = "Subnets from which Talos picks the node IP (kubelet) and the etcd address of control planes. Empty uses network.cidr when set. Set it when the nodes have several networks."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for subnet in var.node_subnets : can(cidrhost(subnet, 0))])
    error_message = "node_subnets entries must be CIDRs."
  }
}

variable "pod_subnets" {
  description = "Pod subnets. Empty keeps the Talos default."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for subnet in var.pod_subnets : can(cidrhost(subnet, 0))])
    error_message = "pod_subnets entries must be CIDRs."
  }
}

variable "service_subnets" {
  description = "Service subnets. Empty keeps the Talos default."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for subnet in var.service_subnets : can(cidrhost(subnet, 0))])
    error_message = "service_subnets entries must be CIDRs."
  }
}

variable "cni" {
  description = "CNI: flannel (the Talos default) or none, to install your own, for example Cilium. With none, nodes stay NotReady until the CNI is installed."
  type        = string
  default     = "flannel"
  nullable    = false

  validation {
    condition     = contains(["flannel", "none"], var.cni)
    error_message = "cni must be flannel or none."
  }
}

variable "disable_kube_proxy" {
  description = "Do not run kube-proxy, because the CNI replaces it (Cilium kube-proxy replacement)."
  type        = bool
  default     = false
  nullable    = false
}

variable "allow_scheduling_on_control_planes" {
  description = "Let workloads run on control planes. Needed for a cluster without workers."
  type        = bool
  default     = false
  nullable    = false
}

variable "api_server_cert_sans" {
  description = "Extra names or IP addresses in the Kubernetes API server certificate. network.vip is added automatically."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "kubelet_extra_args" {
  description = "Extra kubelet arguments, for example { \"rotate-server-certificates\" = \"true\" } (it needs a CSR approver in the cluster)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "node_labels" {
  description = "Kubernetes labels for every node. A node's own labels win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "encryption" {
  description = <<-EOT
    Encrypt the STATE and EPHEMERAL volumes with LUKS2. Null encrypts nothing. Changing it on a running node needs a wipe of the volumes.
    - method: tpm (key sealed in the TPM, needs a virtual TPM) or node_id (key derived from the node identity, protects less).
    - tpm_require_secureboot: refuse to enroll the key when SecureBoot is off.
  EOT
  type = object({
    method                 = optional(string, "tpm")
    tpm_require_secureboot = optional(bool, false)
  })
  default = null

  validation {
    condition     = var.encryption == null ? true : contains(["tpm", "node_id"], var.encryption.method)
    error_message = "encryption.method must be tpm or node_id."
  }
}

variable "oidc" {
  description = <<-EOT
    OIDC authentication of the Kubernetes API (an AuthenticationConfiguration file on control planes). Null adds none.
    Needs Kubernetes 1.34 or later (the v1 API). A change restarts the control planes: the file is read at start.
    - issuer_url: https URL of the identity provider.
    - client_id: expected audience.
    - ca_certificate: PEM of the CA that signed the provider certificate. Null uses the system CAs.
    - username_claim, username_prefix, groups_claim, groups_prefix: how claims map to Kubernetes users and groups.
  EOT
  type = object({
    issuer_url      = string
    client_id       = string
    ca_certificate  = optional(string)
    username_claim  = optional(string, "email")
    username_prefix = optional(string, "oidc:")
    groups_claim    = optional(string, "groups")
    groups_prefix   = optional(string, "oidc:")
  })
  default = null

  validation {
    condition     = var.oidc == null ? true : can(regex("^https://[^[:space:]]+$", var.oidc.issuer_url))
    error_message = "oidc.issuer_url must be an https:// URL."
  }

  validation {
    condition     = var.oidc == null ? true : trimspace(var.oidc.client_id) != ""
    error_message = "oidc.client_id must not be empty."
  }

  validation {
    condition     = var.oidc == null ? true : try(tonumber(split(".", trimprefix(var.kubernetes_version, "v"))[1]) >= 34, false)
    error_message = "OIDC authentication needs Kubernetes 1.34 or later: the AuthenticationConfiguration v1 API does not exist before."
  }
}

variable "expose_control_plane_metrics" {
  description = "Expose etcd, kube-scheduler and kube-controller-manager metrics on all addresses of control planes, for Prometheus. Restrict access to them with a firewall: they are not authenticated for etcd."
  type        = bool
  default     = false
  nullable    = false
}

variable "config_patches" {
  description = "Extra Talos configuration patches, as YAML strings, applied after the module's own patches so they can override them: all nodes, control planes only, workers only."
  type = object({
    all          = optional(list(string), [])
    controlplane = optional(list(string), [])
    worker       = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "secrets" {
  description = "Machine secrets and client configuration created elsewhere, for example read from a secret manager. Null makes the module generate them: the Terraform state then holds the cluster PKI, so it must be encrypted and backed up. Use the machine_secrets and client_configuration outputs to store them."
  type = object({
    machine_secrets = any
    client_configuration = object({
      ca_certificate     = string
      client_certificate = string
      client_key         = string
    })
  })
  default   = null
  sensitive = true
}

variable "kubeconfig" {
  description = "Kubeconfig used to drain nodes during an OS upgrade. Only needed with drain_on_upgrade. It is write-only and never stored: pass the kubeconfig_raw of an ephemeral talos_cluster_kubeconfig, which is built from the machine secrets without reaching the cluster."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

variable "drain_on_upgrade" {
  description = "Cordon and drain a node before its OS upgrade, then uncordon it. Needs the kubeconfig variable and a healthy cluster. Keep false when creating a cluster: the provider asks for a kubeconfig when installer_image is set, and none exists yet."
  type        = bool
  default     = false
  nullable    = false
}

variable "reboot_mode" {
  description = "Reboot mode for OS upgrades: DEFAULT or POWERCYCLE. Null keeps the provider default."
  type        = string
  default     = null

  validation {
    condition     = var.reboot_mode == null ? true : contains(["DEFAULT", "POWERCYCLE"], var.reboot_mode)
    error_message = "reboot_mode must be DEFAULT or POWERCYCLE."
  }
}

variable "ignore_kubernetes_upgrade_drift" {
  description = "Let talos_cluster alone upgrade the Kubernetes components, so that a kubernetes_version change does not make every node re-apply its configuration at once. The provider documents it as experimental."
  type        = bool
  default     = true
  nullable    = false
}
