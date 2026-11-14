# A hardened cluster for a Cilium install: no CNI, no kube-proxy, LUKS2 disk encryption sealed in the TPM, OIDC login and metrics for Prometheus.
# The machines need SecureBoot and a TPM 2.0 (terraform-proxmox-talos-vm: firmware = { bios = "ovmf" } and tpm = {}),
# and a SecureBoot installer image (terraform-talos-image with secureboot enabled).
#
# Settings that are not options of the module go through config_patches (YAML, applied last).

terraform {
  required_version = ">= 1.15"
}

variable "oidc_ca_certificate" {
  description = "PEM of the CA that signed the OIDC provider certificate."
  type        = string
  default     = null
}

module "cluster" {
  source = "../../"

  cluster_name       = "prod"
  cluster_endpoint   = "https://192.0.2.2:6443"
  talos_version      = "v1.13"
  kubernetes_version = "v1.37.2"
  installer_image    = "factory.talos.dev/installer-secureboot/SCHEMATIC_ID:v1.14.6"
  install_disk       = "/dev/sda"

  nodes = {
    "prod-cp-1"     = { role = "controlplane", ip = "192.0.2.3", labels = { "topology.kubernetes.io/zone" = "pve-01" } }
    "prod-cp-2"     = { role = "controlplane", ip = "192.0.2.4", labels = { "topology.kubernetes.io/zone" = "pve-02" } }
    "prod-cp-3"     = { role = "controlplane", ip = "192.0.2.5", labels = { "topology.kubernetes.io/zone" = "pve-03" } }
    "prod-worker-1" = { role = "worker", ip = "192.0.2.6", labels = { "topology.kubernetes.io/zone" = "pve-01" } }
  }

  network     = { cidr = "192.0.2.0/27", gateway = "192.0.2.1", vip = "192.0.2.2" }
  nameservers = ["192.0.2.53", "192.0.2.1"]

  cni                = "none"
  disable_kube_proxy = true
  node_labels        = { "topology.kubernetes.io/region" = "lab" }

  # Needs a kubelet serving certificate approver in the cluster.
  kubelet_extra_args = { "rotate-server-certificates" = "true" }

  encryption = { method = "tpm", tpm_require_secureboot = true }

  oidc = {
    issuer_url     = "https://dex.example.test"
    client_id      = "kubernetes"
    ca_certificate = var.oidc_ca_certificate
  }

  expose_control_plane_metrics = true

  config_patches = {
    all = [yamlencode({ machine = { sysctls = { "vm.max_map_count" = "262144" } } })]
  }
}

output "controlplane_ips" {
  value = module.cluster.controlplane_ips
}
