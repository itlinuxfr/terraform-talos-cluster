variable "talos_cluster_name" {
  type        = string
  description = "Talos Cluster Name"
  validation {
    condition     = length(var.talos_cluster_name) > 0
    error_message = "Cluster name must not be empty."
  }
}

variable "talos_cni" {
  type        = string
  default     = "flannel"
  description = "Talos Cluster Network Plugin"
  validation {
    condition     = length(var.talos_cni) > 0
    error_message = "CNI name must not be empty."
  }
}

variable "talos_vip" {
  type        = string
  description = "Talos Cluster Kube APIServer VIP"
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.talos_vip))
    error_message = "VIP must be a valid IPv4 address."
  }
}

variable "talos_api_port" {
  type        = number
  default     = 6443
  description = "Talos Cluster Kube APIServer Port"
  validation {
    condition     = var.talos_api_port > 0 && var.talos_api_port < 65536
    error_message = "API port must be a valid port number (1-65535)."
  }
}

variable "talos_version" {
  type        = string
  default     = "v1.11.3"
  description = "Talos Version"
  validation {
    condition     = can(regex("^v", var.talos_version))
    error_message = "Talos version must start with 'v' (e.g. v1.8.0)."
  }
}

variable "talos_controlplanes" {
  type = map(object({
    ip          = string
    hostname    = string
    interface   = string
    disk        = string
    node_labels = optional(map(string), {})
  }))
  description = "Map of control plane nodes"
  validation {
    condition     = alltrue([for k, v in var.talos_controlplanes : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", v.ip))])
    error_message = "All control plane IPs must be valid IPv4 addresses."
  }
}

variable "talos_workernodes" {
  type = map(object({
    ip          = string
    hostname    = string
    interface   = string
    disk        = string
    node_labels = optional(map(string), {})
  }))
  description = "Map of worker nodes"
  validation {
    condition     = alltrue([for k, v in var.talos_workernodes : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", v.ip))])
    error_message = "All worker node IPs must be valid IPv4 addresses."
  }
}

variable "cluster_pod_subnets" {
  description = "List of CIDR blocks for pod subnets"
  type        = list(string)
  default     = ["172.16.0.0/16"]
  validation {
    condition     = alltrue([for cidr in var.cluster_pod_subnets : can(cidrhost(cidr, 0))])
    error_message = "All pod subnets must be valid CIDR notation."
  }
}

variable "cluster_service_subnets" {
  description = "List of CIDR blocks for service subnets"
  type        = list(string)
  default     = ["172.10.0.0/16"]
  validation {
    condition     = alltrue([for cidr in var.cluster_service_subnets : can(cidrhost(cidr, 0))])
    error_message = "All service subnets must be valid CIDR notation."
  }
}

variable "cluster_dns_domain" {
  description = "The DNS domain for the cluster"
  type        = string
  default     = "cluster.local"
  validation {
    condition     = length(var.cluster_dns_domain) > 0
    error_message = "DNS domain must not be empty."
  }
}

variable "talos_kernel_args" {
  description = "List of extra kernel arguments to pass to the node"
  type        = list(string)
  default     = []
}

variable "talos_inline_manifests" {
  description = "List of inline manifests to apply to the cluster"
  type = list(object({
    name     = string
    contents = string
  }))
  default = []
}
