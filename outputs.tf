output "kubeconfig" {
  value     = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive = true
  description = "Raw Kubeconfig data"
}

output "kubeconfig_client_configuration" {
  value     = talos_cluster_kubeconfig.cluster.kubernetes_client_configuration
  sensitive = true
  description = "Kubernetes client configuration"
}

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
  description = "Talos client configuration"
}
