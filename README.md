# terraform-talos-cluster

Builds a [Talos Linux](https://www.talos.dev) Kubernetes cluster on machines that already exist and boot Talos. The module generates the secrets and the
machine configuration of each node, applies it, bootstraps etcd, upgrades Kubernetes and the Talos OS on request, and returns the kubeconfig and the talosconfig.
It does not create the machines or the Talos image: use `terraform-proxmox-talos-vm`, `terraform-proxmox-download-file` and `terraform-talos-image` for that.

## Usage

```hcl
module "cluster" {
  source = "git::https://github.com/itlinuxfr/terraform-talos-cluster.git?ref=v1.0.0"

  cluster_name       = "demo"
  cluster_endpoint   = "https://192.0.2.2:6443"
  kubernetes_version = "v1.37.2"

  nodes = {
    "demo-cp-1"     = { role = "controlplane", ip = "192.0.2.3" }
    "demo-cp-2"     = { role = "controlplane", ip = "192.0.2.4" }
    "demo-cp-3"     = { role = "controlplane", ip = "192.0.2.5" }
    "demo-worker-1" = { role = "worker", ip = "192.0.2.6" }
  }

  network = { cidr = "192.0.2.0/27", gateway = "192.0.2.1", vip = "192.0.2.2" }
}
```

See [`examples/`](examples/): a basic cluster, a hardened one (no CNI, no kube-proxy, LUKS2 sealed in a TPM, OIDC, metrics), and an OS upgrade with drain.

## How it works
The module has typed options for the common settings (versions, nodes, network, CNI, kube-proxy, labels and taints, disk encryption, OIDC, control plane metrics)
and takes any other setting as YAML patches (`config_patches` for all nodes, control planes or workers, and `config_patches` per node). Patches apply in this order,
so yours can override the module's: base, control plane, disk encryption, node, then yours.

Order of creation: control planes, then `talos_cluster` (etcd bootstrap, wait for the Talos layer, Kubernetes upgrades), then workers.
`talos_cluster` waits for etcd, apid and kubelet, not for Kubernetes nodes to be Ready, so `cni = "none"` works until you install the CNI.

## Upgrading, and what to know about `talos_machine`
Nodes use `talos_machine`, which applies the configuration, waits for the node and, when `installer_image` is set, keeps the Talos version in sync.
Checked in the provider source (v0.12.0):
- **Configuration is always applied in `AUTO` mode.** A change that needs a restart (for example the OIDC file, kernel arguments) restarts the node at once, without drain.
  There is no staged mode.
- **Run `terraform apply -parallelism=1` for any change that restarts nodes.** `talos_machine` waits for each node to be ready again, so nodes restart one after the other and etcd keeps its quorum.
  Without it, several nodes can restart together. The provider documentation gives the same advice.
- **Drain needs a kubeconfig**, and the provider asks for one when `installer_image` is set and drain is not disabled. The module therefore keeps `drain_on_upgrade = false`
  by default, which is what a new cluster needs. For an upgrade set it to `true` and pass `kubeconfig` from an ephemeral `talos_cluster_kubeconfig`
  (it is built from the machine secrets, without reaching the cluster; see `examples/upgrade`).
- **Talos 1.14 and later only.** The module generates the Talos v1.14 configuration (the new multi-document format) and patches the documents the provider generates (`UnattendedInstallConfig`,
  `ResolverConfig`, `KubeletConfig`, `KubeNodeConfig`, `KubeAPIServerConfig`...). It never writes the deprecated `v1alpha1` field of a setting that has a document. A later Talos release runs with this
  configuration until a release of the module moves it. Settings you pass through `config_patches` must be documents too (for example `SysctlConfig`, not `machine.sysctls`).
- Checked on a real cluster: one control plane and one worker on Talos 1.14.6 (SecureBoot, TPM-sealed LUKS2 unlocked after a reboot, virtual IP, flannel, kube-proxy, OIDC configuration, control-plane scheduling, labels, kubelet arguments, metrics, a caller `SysctlConfig`). A taint on an already registered worker is refused by Kubernetes, and the etcd metrics port opens after the next reboot of a control plane.
- The primary network card is renamed `net0` by a `LinkAliasConfig` (it matches the one physical Ethernet link), and the static address, the default route and the virtual IP are set on it.
  A machine with several physical cards needs its own patches. `allow_scheduling_on_control_planes` deletes and rewrites the generated `KubeNodeConfig` (a merge patch cannot remove the taint),
  which also drops its `exclude-from-external-load-balancers` label. etcd has no document yet: its settings stay in the v1alpha1 `cluster.etcd` section.

## Secrets and state
By default the module generates the cluster secrets, so **the Terraform state holds the cluster PKI**: use an encrypted remote backend and back it up.
To keep the secrets elsewhere, pass them in `secrets` (for example read from a secret manager), and store the `machine_secrets` and `client_configuration` outputs
the first time. Losing the machine secrets means losing access to the cluster.

## Moving an existing cluster to this module
Not tested on a real cluster. The provider (v0.12.0) has no state migration for `talos_machine` and `talos_cluster`, so they are created, not moved:
- `talos_machine_secrets` and `talos_cluster_kubeconfig` keep their type: use `moved` blocks (the secrets are at `talos_machine_secrets.this[0]` in the module).
- `talos_machine_configuration_apply` and `talos_machine_bootstrap` must leave the state with `terraform state rm`. Creating `talos_cluster` on a bootstrapped cluster is safe: the bootstrap is idempotent.
  Creating `talos_machine` applies the generated configuration to the running node. If it differs from the current one, the node can restart: compare the configurations first
  and apply with `-parallelism=1`.

## Contributing
Read [`AGENTS.md`](AGENTS.md) for conventions and commands, and [`SECURITY.md`](SECURITY.md) for security rules.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.15 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | >= 0.12.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_talos"></a> [talos](#provider\_talos) | >= 0.12.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [talos_cluster.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/cluster) | resource |
| [talos_cluster_kubeconfig.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/cluster_kubeconfig) | resource |
| [talos_machine.controlplane](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine) | resource |
| [talos_machine.worker](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_secrets) | resource |
| [talos_client_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/client_configuration) | data source |
| [talos_machine_configuration.node](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | URL of the Kubernetes API that nodes and clients use, for example https://192.0.2.2:6443. With several control planes, use a virtual IP or a load balancer, never a single node. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster. It ends up in the talosconfig and in the kubeconfig. | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version of the cluster, for example v1.37.2. Always set it: the provider default can be newer than the version you tested. Changing it runs the Talos upgrade-k8s procedure on a running cluster. | `string` | n/a | yes |
| <a name="input_nodes"></a> [nodes](#input\_nodes) | Nodes, keyed by name. The name is the Kubernetes node name when the machine takes its hostname from the platform.<br/>- role: controlplane or worker. The number of control planes must be odd (etcd quorum).<br/>- ip: IP address of the node, reachable by Terraform on the Talos API (port 50000).<br/>- install\_disk, image: override the cluster-wide values.<br/>- labels, taints: Kubernetes node labels and taints (a taint value is "value:effect", for example "dedicated:NoSchedule"). A worker taint is applied when the node registers: Kubernetes (NodeRestriction) refuses a change on a node that is already registered, so set it before creating the node or recreate the node.<br/>- config\_patches: extra YAML patches for this node only. | <pre>map(object({<br/>    role           = string<br/>    ip             = string<br/>    install_disk   = optional(string)<br/>    image          = optional(string)<br/>    labels         = optional(map(string), {})<br/>    taints         = optional(map(string), {})<br/>    config_patches = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_allow_scheduling_on_control_planes"></a> [allow\_scheduling\_on\_control\_planes](#input\_allow\_scheduling\_on\_control\_planes) | Let workloads run on control planes. Needed for a cluster without workers. | `bool` | `false` | no |
| <a name="input_api_server_cert_sans"></a> [api\_server\_cert\_sans](#input\_api\_server\_cert\_sans) | Extra names or IP addresses in the Kubernetes API server certificate. network.vip is added automatically. | `list(string)` | `[]` | no |
| <a name="input_cni"></a> [cni](#input\_cni) | CNI: flannel (the Talos default) or none, to install your own, for example Cilium. With none, nodes stay NotReady until the CNI is installed. | `string` | `"flannel"` | no |
| <a name="input_config_patches"></a> [config\_patches](#input\_config\_patches) | Extra Talos configuration patches, as YAML strings, applied after the module's own patches so they can override them: all nodes, control planes only, workers only. | <pre>object({<br/>    all          = optional(list(string), [])<br/>    controlplane = optional(list(string), [])<br/>    worker       = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_disable_kube_proxy"></a> [disable\_kube\_proxy](#input\_disable\_kube\_proxy) | Do not run kube-proxy, because the CNI replaces it (Cilium kube-proxy replacement). | `bool` | `false` | no |
| <a name="input_drain_on_upgrade"></a> [drain\_on\_upgrade](#input\_drain\_on\_upgrade) | Cordon and drain a node before its OS upgrade, then uncordon it. Needs the kubeconfig variable and a healthy cluster. Keep false when creating a cluster: the provider asks for a kubeconfig when installer\_image is set, and none exists yet. | `bool` | `false` | no |
| <a name="input_encryption"></a> [encryption](#input\_encryption) | Encrypt the STATE and EPHEMERAL volumes with LUKS2. Null encrypts nothing. Changing it on a running node needs a wipe of the volumes.<br/>- method: tpm (key sealed in the TPM, needs a virtual TPM) or node\_id (key derived from the node identity, protects less).<br/>- tpm\_require\_secureboot: refuse to enroll the key when SecureBoot is off. | <pre>object({<br/>    method                 = optional(string, "tpm")<br/>    tpm_require_secureboot = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_expose_control_plane_metrics"></a> [expose\_control\_plane\_metrics](#input\_expose\_control\_plane\_metrics) | Expose etcd, kube-scheduler and kube-controller-manager metrics on all addresses of control planes, for Prometheus. Restrict access to them with a firewall: they are not authenticated for etcd. etcd reads its arguments at start: on a running cluster the etcd port opens after the next reboot of each control plane. | `bool` | `false` | no |
| <a name="input_ignore_kubernetes_upgrade_drift"></a> [ignore\_kubernetes\_upgrade\_drift](#input\_ignore\_kubernetes\_upgrade\_drift) | Let talos\_cluster alone upgrade the Kubernetes components, so that a kubernetes\_version change does not make every node re-apply its configuration at once. The provider documents it as experimental. | `bool` | `true` | no |
| <a name="input_install_disk"></a> [install\_disk](#input\_install\_disk) | Disk that Talos installs on, for example /dev/sda. Null keeps the Talos default. A node can override it. | `string` | `null` | no |
| <a name="input_installer_image"></a> [installer\_image](#input\_installer\_image) | Talos installer image, for example from the installer\_image output of terraform-talos-image. When set, Terraform also manages the Talos version: changing it upgrades the nodes. Null leaves the installed version alone. A node can override it. | `string` | `null` | no |
| <a name="input_kubeconfig"></a> [kubeconfig](#input\_kubeconfig) | Kubeconfig used to drain nodes during an OS upgrade. Only needed with drain\_on\_upgrade. It is write-only and never stored: pass the kubeconfig\_raw of an ephemeral talos\_cluster\_kubeconfig, which is built from the machine secrets without reaching the cluster. | `string` | `null` | no |
| <a name="input_kubelet_extra_args"></a> [kubelet\_extra\_args](#input\_kubelet\_extra\_args) | Extra kubelet arguments, for example { "rotate-server-certificates" = "true" } (it needs a CSR approver in the cluster). | `map(string)` | `{}` | no |
| <a name="input_nameservers"></a> [nameservers](#input\_nameservers) | DNS servers of the nodes. Empty keeps the ones from the platform. | `list(string)` | `[]` | no |
| <a name="input_network"></a> [network](#input\_network) | Static network of the nodes. Null leaves the network to the platform (DHCP or cloud-init).<br/>- cidr: network of the nodes, for example 192.0.2.0/27.<br/>- gateway: default gateway.<br/>- vip: Talos virtual IP shared by the control planes, which should match the host of cluster\_endpoint. Null adds none.<br/>The module sets a static address on the first physical interface of each node and the vip on control planes. | <pre>object({<br/>    cidr    = string<br/>    gateway = string<br/>    vip     = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_node_labels"></a> [node\_labels](#input\_node\_labels) | Kubernetes labels for every node. A node's own labels win. | `map(string)` | `{}` | no |
| <a name="input_node_subnets"></a> [node\_subnets](#input\_node\_subnets) | Subnets from which Talos picks the node IP (kubelet) and the etcd address of control planes. Empty uses network.cidr when set. Set it when the nodes have several networks. | `list(string)` | `[]` | no |
| <a name="input_oidc"></a> [oidc](#input\_oidc) | OIDC authentication of the Kubernetes API (an AuthenticationConfiguration file on control planes). Null adds none.<br/>Needs Kubernetes 1.34 or later (the v1 API). A change restarts the control planes: the file is read at start.<br/>- issuer\_url: https URL of the identity provider.<br/>- client\_id: expected audience.<br/>- ca\_certificate: PEM of the CA that signed the provider certificate. Null uses the system CAs.<br/>- username\_claim, username\_prefix, groups\_claim, groups\_prefix: how claims map to Kubernetes users and groups. | <pre>object({<br/>    issuer_url      = string<br/>    client_id       = string<br/>    ca_certificate  = optional(string)<br/>    username_claim  = optional(string, "email")<br/>    username_prefix = optional(string, "oidc:")<br/>    groups_claim    = optional(string, "groups")<br/>    groups_prefix   = optional(string, "oidc:")<br/>  })</pre> | `null` | no |
| <a name="input_pod_subnets"></a> [pod\_subnets](#input\_pod\_subnets) | Pod subnets. Empty keeps the Talos default. | `list(string)` | `[]` | no |
| <a name="input_reboot_mode"></a> [reboot\_mode](#input\_reboot\_mode) | Reboot mode for OS upgrades: DEFAULT or POWERCYCLE. Null keeps the provider default. | `string` | `null` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Machine secrets and client configuration created elsewhere, for example read from a secret manager. Null makes the module generate them: the Terraform state then holds the cluster PKI, so it must be encrypted and backed up. Use the machine\_secrets and client\_configuration outputs to store them. | <pre>object({<br/>    machine_secrets = any<br/>    client_configuration = object({<br/>      ca_certificate     = string<br/>      client_certificate = string<br/>      client_key         = string<br/>    })<br/>  })</pre> | `null` | no |
| <a name="input_service_subnets"></a> [service\_subnets](#input\_service\_subnets) | Service subnets. Empty keeps the Talos default. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_client_configuration"></a> [client\_configuration](#output\_client\_configuration) | Talos client certificate and key. Store them in a secret manager to reuse them as the secrets input. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | URL of the Kubernetes API. |
| <a name="output_controlplane_ips"></a> [controlplane\_ips](#output\_controlplane\_ips) | IP addresses of the control planes, sorted by node name. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig of the cluster. |
| <a name="output_machine_secrets"></a> [machine\_secrets](#output\_machine\_secrets) | Talos machine secrets (the cluster PKI). Store them in a secret manager to reuse them as the secrets input. Losing them means losing the cluster. |
| <a name="output_node_ips"></a> [node\_ips](#output\_node\_ips) | IP address of each node, by node name. |
| <a name="output_talosconfig"></a> [talosconfig](#output\_talosconfig) | talosconfig for talosctl, with the control plane IPs as endpoints and all node IPs as nodes. |
<!-- END_TF_DOCS -->
