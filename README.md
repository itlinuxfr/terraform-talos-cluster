<!-- BEGIN_TF_DOCS -->
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

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.0 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | 0.9.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [talos_cluster_kubeconfig.cluster](https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/cluster_kubeconfig) | resource |
| [talos_machine_bootstrap.this](https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/machine_bootstrap) | resource |
| [talos_machine_configuration_apply.control_plane](https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_configuration_apply.worker](https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/machine_secrets) | resource |
| [talos_client_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/data-sources/client_configuration) | data source |
| [talos_machine_configuration.control_plane](https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.worker](https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_dns_domain"></a> [cluster\_dns\_domain](#input\_cluster\_dns\_domain) | The DNS domain for the cluster | `string` | `"cluster.local"` | no |
| <a name="input_cluster_pod_subnets"></a> [cluster\_pod\_subnets](#input\_cluster\_pod\_subnets) | List of CIDR blocks for pod subnets | `list(string)` | <pre>[<br/>  "172.16.0.0/16"<br/>]</pre> | no |
| <a name="input_cluster_service_subnets"></a> [cluster\_service\_subnets](#input\_cluster\_service\_subnets) | List of CIDR blocks for service subnets | `list(string)` | <pre>[<br/>  "172.10.0.0/16"<br/>]</pre> | no |
| <a name="input_talos_api_port"></a> [talos\_api\_port](#input\_talos\_api\_port) | Talos Cluster Kube APIServer Port | `number` | `6443` | no |
| <a name="input_talos_cluster_name"></a> [talos\_cluster\_name](#input\_talos\_cluster\_name) | Talos Cluster Name | `string` | n/a | yes |
| <a name="input_talos_cni"></a> [talos\_cni](#input\_talos\_cni) | Talos Cluster Network Plugin | `string` | `"flannel"` | no |
| <a name="input_talos_controlplanes"></a> [talos\_controlplanes](#input\_talos\_controlplanes) | Map of control plane nodes | <pre>map(object({<br/>    ip          = string<br/>    hostname    = string<br/>    interface   = string<br/>    disk        = string<br/>    node_labels = optional(map(string), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_talos_inline_manifests"></a> [talos\_inline\_manifests](#input\_talos\_inline\_manifests) | List of inline manifests to apply to the cluster | <pre>list(object({<br/>    name     = string<br/>    contents = string<br/>  }))</pre> | `[]` | no |
| <a name="input_talos_kernel_args"></a> [talos\_kernel\_args](#input\_talos\_kernel\_args) | List of extra kernel arguments to pass to the node | `list(string)` | `[]` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Talos Version | `string` | `"v1.11.3"` | no |
| <a name="input_talos_vip"></a> [talos\_vip](#input\_talos\_vip) | Talos Cluster Kube APIServer VIP | `string` | n/a | yes |
| <a name="input_talos_workernodes"></a> [talos\_workernodes](#input\_talos\_workernodes) | Map of worker nodes | <pre>map(object({<br/>    ip          = string<br/>    hostname    = string<br/>    interface   = string<br/>    disk        = string<br/>    node_labels = optional(map(string), {})<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Raw Kubeconfig data |
| <a name="output_kubeconfig_client_configuration"></a> [kubeconfig\_client\_configuration](#output\_kubeconfig\_client\_configuration) | Kubernetes client configuration |
| <a name="output_talosconfig"></a> [talosconfig](#output\_talosconfig) | Talos client configuration |
<!-- END_TF_DOCS -->
