# =============================================================================
# Required providers + version constraints for this module.
#
# Why pin: Terraform providers are independently versioned. Without pins,
# `terraform init` in two weeks' time might pick up a breaking provider
# upgrade and surprise everyone. `~> 2.15` means ">= 2.15.0, < 3.0.0" -
# compatible minor upgrades only.
#
# Note: we do NOT declare `provider "helm" {}` etc. here; this is a SHARED
# module. The provider CONFIG (kubeconfig path, auth) is set by the caller
# (envs/local or envs/azure-dev). Terraform inherits provider config from
# the caller when a module doesn't declare its own.
# =============================================================================

terraform {
  # Require Terraform 1.6+ for `moved` blocks + validation improvements used
  # elsewhere in the repo. Bump cautiously.
  required_version = ">= 1.6.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    # alekc/kubectl (not the hashicorp community one) applies raw YAML and
    # handles CRDs that don't exist at plan time - essential for applying
    # Argo CD's own Application CRD right after installing the Argo CD chart.
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }
}
