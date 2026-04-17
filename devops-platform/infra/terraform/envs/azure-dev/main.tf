# =============================================================================
# envs/azure-dev: the "cloud" environment.
#
# Mirror of envs/local, but points at AKS instead of kind. Same
# platform-bootstrap module runs on top.
#
# Prerequisite: `az login` completed in this shell. The azurerm provider
# reads creds from the Azure CLI's cached auth.
#
# Run:      terraform init && terraform apply
# Teardown: terraform destroy   (tears down RG + AKS + ACR + logs)
# =============================================================================

# ---- 1. AKS cluster ----
module "aks" {
  source = "../../modules/aks-cluster"

  prefix       = var.prefix
  location     = var.location
  node_count   = var.node_count
  node_vm_size = var.node_vm_size
}

# ---- 2. Provider wiring ----
# AKS kube_config values come back base64-encoded from the Azure API, so we
# decode before passing to the providers. (kind doesn't base64-encode, hence
# the difference vs envs/local/main.tf.)

provider "kubernetes" {
  host                   = module.aks.cluster_host
  client_certificate     = base64decode(module.aks.client_certificate)
  client_key             = base64decode(module.aks.client_key)
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.aks.cluster_host
    client_certificate     = base64decode(module.aks.client_certificate)
    client_key             = base64decode(module.aks.client_key)
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = module.aks.cluster_host
  client_certificate     = base64decode(module.aks.client_certificate)
  client_key             = base64decode(module.aks.client_key)
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  load_config_file       = false
}

# ---- 3. Platform bootstrap ----
# SAME module as local. Differences:
#   - ingress_service_type = LoadBalancer (Azure provisions a real LB).
#   - depends_on = AKS (provider wiring alone doesn't create an explicit
#     dependency on the cluster CREATION - without this, Terraform might
#     schedule namespace creation before the cluster is Ready).
module "platform" {
  source = "../../modules/platform-bootstrap"

  gitops_repo_url         = var.gitops_repo_url
  gitops_repo_revision    = var.gitops_repo_revision
  gitops_app_of_apps_path = "gitops/argocd"
  ingress_service_type    = "LoadBalancer"
  enable_sealed_secrets   = true

  depends_on = [module.aks]
}
