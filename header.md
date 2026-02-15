[![terraform-docs](https://github.com/itlinuxfr/terraform-talos-cluster/actions/workflows/documentation.yaml/badge.svg)](https://github.com/itlinuxfr/terraform-talos-cluster/actions/workflows/documentation.yaml)
[![terraform-lint](https://github.com/itlinuxfr/terraform-talos-cluster/actions/workflows/tflint.yaml/badge.svg)](https://github.com/itlinuxfr/terraform-talos-cluster/actions/workflows/tflint.yaml)
[![Provider: siderolabs/talos](https://img.shields.io/badge/provider-siderolabs%2Ftalos-623CE4?logo=terraform)](https://registry.terraform.io/providers/siderolabs/talos/latest)
[![Provider: siderolabs/talos v0.9.0](https://img.shields.io/badge/provider%3A%20siderolabs%2Ftalos-v0.9.0-623CE4?logo=terraform)](https://registry.terraform.io/providers/siderolabs/talos)

# Usage

```hcl
module "talos_cluster" {
  source = "./modules/talos_cluster"

  talos_cluster_name = "my-cluster"
  talos_vip          = "192.168.1.100"
  talos_version      = "v1.11.3"

  talos_controlplanes = {
    "cp-1" = {
      ip        = "192.168.1.101"
      hostname  = "cp-1"
      interface = "eth0"
      disk      = "/dev/vda"
      node_labels = {
        "rack" = "zone-a"
      }
    }
  }

  talos_workernodes = {
    "worker-1" = {
      ip        = "192.168.1.102"
      hostname  = "worker-1"
      interface = "eth0"
      disk      = "/dev/vda"
      node_labels = {
        "rack" = "zone-b"
      }
    }
  }

  # Optional Inline Manifests (e.g. CSR Approver)
  talos_inline_manifests = [
    {
      name     = "kubelet-csr-approver"
      contents = file("${path.module}/files/csr-approver.yaml")
    }
  ]

  # Optional Network Configuration
  cluster_pod_subnets     = ["10.244.0.0/16"]
  cluster_service_subnets = ["10.96.0.0/12"]
  cluster_dns_domain      = "cluster.local"
}
```
