# =============================================================================
# envs/local: the "laptop" environment.
#
# This root module:
#   1) creates a kind cluster
#   2) wires up the k8s/helm/kubectl providers against it (reading creds
#      straight from module outputs, NOT from kubeconfig - avoids a
#      chicken-and-egg at plan time)
#   3) installs platform-bootstrap on top
#
# Run:   terraform init && terraform apply
# Teardown: terraform destroy   (removes the Docker container entirely)
# =============================================================================

# ---- 1. Cluster ----
module "cluster" {
  source = "../../modules/kind-cluster"

  cluster_name    = var.cluster_name
  kubeconfig_path = "~/.kube/${var.cluster_name}.kubeconfig"
}

# ---- 2. Provider wiring ----
# We set credentials from MODULE OUTPUTS, not from a kubeconfig file, so:
#   - Terraform doesn't try to read a file that doesn't exist yet.
#   - Each `terraform plan` doesn't drift based on whatever context happens
#     to be active in ~/.kube/config.
#
# All three providers (kubernetes / helm / kubectl) get IDENTICAL config
# because they all target the same cluster.

provider "kubernetes" {
  host                   = module.cluster.endpoint
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.endpoint
    client_certificate     = module.cluster.client_certificate
    client_key             = module.cluster.client_key
    cluster_ca_certificate = module.cluster.cluster_ca_certificate
  }
}

provider "kubectl" {
  host                   = module.cluster.endpoint
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
  # load_config_file=false prevents alekc/kubectl from falling back to
  # ~/.kube/config if the inline config has issues. Safer in CI.
  load_config_file = false
}

# ---- 3. Platform bootstrap ----
# Same module we use on AKS. The ONLY differences are:
#   - ingress_service_type = NodePort (kind has no cloud LB)
#   - enable_sealed_secrets = true   (we don't have Azure Key Vault locally)
# This is the "promote from laptop to prod" demo: one module, two env-specific
# value overrides.
module "platform" {
  source = "../../modules/platform-bootstrap"

  gitops_repo_url         = var.gitops_repo_url
  gitops_repo_revision    = var.gitops_repo_revision
  gitops_app_of_apps_path = "gitops/argocd"
  ingress_service_type    = "NodePort"
  enable_sealed_secrets   = true
}
