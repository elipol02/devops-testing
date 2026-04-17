# Outputs for the azure-dev env. `get_kubeconfig_cmd` is the main one - run
# it after `terraform apply` to get kubectl pointed at the new cluster.

output "resource_group_name" {
  value = module.aks.resource_group_name
}

output "cluster_name" {
  value = module.aks.cluster_name
}

# CI needs this to tag/push images to the per-cluster ACR.
output "acr_login_server" {
  value = module.aks.acr_login_server
}

# Copy-pasteable: `terraform output -raw get_kubeconfig_cmd | bash`.
output "get_kubeconfig_cmd" {
  value = "az aks get-credentials --resource-group ${module.aks.resource_group_name} --name ${module.aks.cluster_name} --overwrite-existing"
}
