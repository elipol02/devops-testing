# =============================================================================
# Outputs = this module's public API. Callers (envs/*) read these to wire
# downstream resources or print hints to the operator.
# =============================================================================

# The argocd namespace name - callers can use this to e.g. wait for argocd
# pods before running an Argo CLI command.
output "argocd_namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}

# Where Grafana + Prometheus live. Callers use this to show port-forward
# hints in runbooks.
output "monitoring_namespace" {
  value = kubernetes_namespace.monitoring.metadata[0].name
}

# Where ingress-nginx lives. On AKS, this is also where the cloud LB's
# public IP materializes (Service type LoadBalancer in this namespace).
output "ingress_namespace" {
  value = kubernetes_namespace.ingress_nginx.metadata[0].name
}

# Sentinel output: its existence (via depends_on) gives callers an explicit
# "the root Application was created" edge to anchor downstream resources
# against, in case they need to wait for the GitOps handoff.
output "root_application_created" {
  value       = true
  description = "True once the root Argo CD Application (app-of-apps) has been applied."
  depends_on  = [kubectl_manifest.root_app]
}
