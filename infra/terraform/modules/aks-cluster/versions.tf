# Provider pins for aks-cluster.
#
# azurerm ~> 4.8: 4.x introduced breaking changes vs 3.x (e.g. implicit
# feature blocks). Ensure the env caller also uses 4.x.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
