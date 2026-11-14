output "kubeconfig" {
  description = "Admin kubeconfig of the cluster."
  type        = string
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "talosconfig for talosctl, with the control plane IPs as endpoints and all node IPs as nodes."
  type        = string
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client certificate and key. Store them in a secret manager to reuse them as the secrets input."
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
  value     = local.client_configuration
  sensitive = true
}

output "machine_secrets" {
  description = "Talos machine secrets (the cluster PKI). Store them in a secret manager to reuse them as the secrets input. Losing them means losing the cluster."
  type        = any
  value       = local.machine_secrets
  sensitive   = true
}

output "controlplane_ips" {
  description = "IP addresses of the control planes, sorted by node name."
  type        = list(string)
  value       = local.controlplane_ips
}

output "node_ips" {
  description = "IP address of each node, by node name."
  type        = map(string)
  value       = { for name, node in var.nodes : name => node.ip }
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API."
  type        = string
  value       = var.cluster_endpoint
}
