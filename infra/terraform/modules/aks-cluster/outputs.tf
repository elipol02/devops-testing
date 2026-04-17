# =============================================================================
# Outputs exposed to the caller env. Shape mirrors kind-cluster/outputs.tf
# on purpose so envs/* can consume either cluster type similarly.
# =============================================================================

output "resource_group_name" {
  # Useful for `az aks get-credentials -g <rg> -n <cluster>` and for
  # `az group delete -n <rg> -y` to nuke everything after a demo.
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

# kube_config[0] = the admin credentials (RBAC-bypass). For a real platform
# you'd use AAD integration and issue per-user credentials instead. This
# is the quickest path to a working kubectl for the demo.
output "cluster_host" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive = true
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].client_certificate
  sensitive = true
}

output "client_key" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].client_key
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive = true
}

# Full kubeconfig YAML, handy for writing to disk or pasting into a tool.
output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}

# ACR FQDN (e.g. devopsplatxyz12.azurecr.io). Used by CI to tag images.
output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

# Required when you later set up federated credentials for Workload Identity
# pods (AAD trusts tokens from this issuer).
output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

# Used by apps that want to send custom logs to the same workspace AKS
# diagnostic logs land in.
output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}
