# A small Talos cluster: three control planes and two workers, on machines that already boot a Talos image.
# In a real project, pin the module source to a tag:
#   source = "git::https://github.com/itlinuxfr/terraform-talos-cluster.git?ref=v1.0.0"
# The relative source is used by CI: it tests the code of the current branch.
#
# Create the machines with terraform-proxmox-talos-vm (one call per node, for_each over the nodes) and the image with terraform-talos-image.

terraform {
  required_version = ">= 1.15"
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
    "demo-worker-2" = { role = "worker", ip = "192.0.2.7" }
  }

  network     = { cidr = "192.0.2.0/27", gateway = "192.0.2.1", vip = "192.0.2.2" }
  nameservers = ["192.0.2.53"]
}

# The outputs are sensitive: write them to files outside the repository, or read them with `terraform output -raw kubeconfig`.
output "kubeconfig" {
  value     = module.cluster.kubeconfig
  sensitive = true
}

output "talosconfig" {
  value     = module.cluster.talosconfig
  sensitive = true
}
