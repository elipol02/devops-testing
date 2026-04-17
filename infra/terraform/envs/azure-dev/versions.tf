# Provider pins for envs/azure-dev. Union of aks-cluster + platform-bootstrap
# requirements, plus azurerm which only the env (not the modules) configures.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.8"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# The `features {}` block is mandatory for azurerm 3.x/4.x even when empty;
# it's where you'd tweak behaviors like "purge Key Vault on destroy."
# Authentication: we DON'T configure creds here - azurerm picks them up from
# the Azure CLI (`az login`), env vars (ARM_*), or a Managed Identity.
provider "azurerm" {
  features {}
}
