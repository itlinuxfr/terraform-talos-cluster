# Extra Talos documents on a cluster: NTP servers (TimeSyncConfig) and a custom CA that the nodes trust (TrustedRootsConfig).
# The module generates the Talos v1.14 configuration of each node. Anything that is not an option of the module goes through
# config_patches: YAML documents merged after the generated ones, in this order: all nodes, then the role, then the node.
#
# The same call works on a new cluster and on a running one. On a running cluster, add the documents, run `terraform plan`
# and check that only talos_machine.* change in place (nothing destroyed or replaced), then `terraform apply -parallelism=1`.
# talos_machine applies in the AUTO mode: if Talos decided that a change needs a restart, the node restarts at once, without drain.
# -parallelism=1 keeps it to one node at a time. To try it first, apply a single control plane with -target.
#
# Everything here is a placeholder: example.com and 192.0.2.0/24 are documentation names, and the CA comes from a variable.
# Never write a real certificate chain or a secret in a repository.

terraform {
  required_version = ">= 1.15"
}

variable "internal_ca_pem" {
  description = "PEM of the internal CA that the nodes must trust (one or several certificates)."
  type        = string
}

locals {
  # NTP servers. useNTS = false because one of the servers is an address: NTS needs host names and servers that support it.
  # Without this document Talos uses its default server (time.cloudflare.com).
  time_sync = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "TimeSyncConfig"
    ntp = {
      servers = ["time.example.com", "192.0.2.123"]
      useNTS  = false
    }
  })

  # A trusted root CA. One document can hold several certificates: use one document per CA to give each its own name.
  trusted_root = yamlencode({
    apiVersion   = "v1alpha1"
    kind         = "TrustedRootsConfig"
    name         = "internal-ca"
    certificates = var.internal_ca_pem
  })
}

module "cluster" {
  source = "../../"

  cluster_name       = "demo"
  cluster_endpoint   = "https://192.0.2.2:6443"
  kubernetes_version = "v1.37.2"

  nodes = {
    "demo-cp-1"     = { role = "controlplane", ip = "192.0.2.3" }
    "demo-cp-2"     = { role = "controlplane", ip = "192.0.2.4" }
    "demo-cp-3"     = { role = "controlplane", ip = "192.0.2.5" }
    "demo-worker-1" = { role = "worker", ip = "192.0.2.6" }
  }

  network     = { cidr = "192.0.2.0/27", gateway = "192.0.2.1", vip = "192.0.2.2" }
  nameservers = ["192.0.2.53"]

  config_patches = {
    # Every node gets the NTP servers and the CA.
    all = [local.time_sync, local.trusted_root]

    # Variants:
    # controlplane = [local.trusted_root]   # control planes only
    # worker       = [local.time_sync]      # workers only
    # One node only: give it config_patches = [local.time_sync] in the nodes map above.
  }
}

output "controlplane_ips" {
  value = module.cluster.controlplane_ips
}
