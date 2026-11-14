# Upgrade the Talos OS of a running cluster, with drain, and keep the cluster secrets outside the Terraform state.
#
# 1. Raise installer_image (the installer_image output of terraform-talos-image).
# 2. Turn drain_on_upgrade on. The kubeconfig for the drain is built from the machine secrets by an ephemeral resource: it is never stored.
# 3. Run `terraform apply -parallelism=1`. talos_machine waits for each node to be ready again, so the nodes upgrade one after the other
#    and etcd keeps its quorum. Without -parallelism=1, several nodes can restart at the same time.
#
# Keep talos_version (the configuration contract) at the version the cluster was created with: it is not the installed version.
# While creating a cluster, leave drain_on_upgrade off: there is no kubeconfig yet.

terraform {
  required_version = ">= 1.15"

  # Declared here because this root module uses an ephemeral resource of the provider itself.
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.12.0"
    }
  }
}

variable "machine_secrets" {
  description = "Machine secrets read from a secret manager."
  type        = any
  sensitive   = true
}

variable "client_configuration" {
  description = "Talos client configuration read from the same secret manager."
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
  sensitive = true
}

ephemeral "talos_cluster_kubeconfig" "drain" {
  machine_secrets = var.machine_secrets
  cluster_name    = "demo"
  endpoint        = "https://192.0.2.2:6443"
}

module "cluster" {
  source = "../../"

  cluster_name       = "demo"
  cluster_endpoint   = "https://192.0.2.2:6443"
  talos_version      = "v1.14"
  kubernetes_version = "v1.37.2"
  installer_image    = "factory.talos.dev/installer/SCHEMATIC_ID:v1.14.6"

  nodes = {
    "demo-cp-1"     = { role = "controlplane", ip = "192.0.2.3" }
    "demo-cp-2"     = { role = "controlplane", ip = "192.0.2.4" }
    "demo-cp-3"     = { role = "controlplane", ip = "192.0.2.5" }
    "demo-worker-1" = { role = "worker", ip = "192.0.2.6" }
  }

  secrets = {
    machine_secrets      = var.machine_secrets
    client_configuration = var.client_configuration
  }

  drain_on_upgrade = true
  kubeconfig       = ephemeral.talos_cluster_kubeconfig.drain.kubeconfig_raw
}
