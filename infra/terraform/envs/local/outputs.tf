# Outputs for humans running `terraform apply` - what to do next.

output "kubeconfig_path" {
  # `export KUBECONFIG=$(terraform output -raw kubeconfig_path)` then kubectl.
  value = module.cluster.kubeconfig_path
}

output "cluster_name" {
  value = module.cluster.cluster_name
}

output "argocd_url" {
  # Reminder: hostnames on .local.test resolve via /etc/hosts, not DNS.
  # Add the two lines shown here so ingress-nginx's Host header routing works.
  value = "http://argocd.local.test (add '127.0.0.1 argocd.local.test grafana.local.test' to your hosts file)"
}
