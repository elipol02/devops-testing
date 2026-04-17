# Inputs for the azure-dev env. Azure credentials come from `az login`
# (the azurerm provider auto-detects); nothing here.

variable "gitops_repo_url" {
  description = "HTTPS URL of the GitOps repo Argo CD should track."
  type        = string
}

variable "gitops_repo_revision" {
  type    = string
  default = "main"
}

# The rest forward straight into the aks-cluster module. Exposed here so
# you can override on the command line without editing module code.

variable "prefix" {
  type    = string
  default = "devopsplat"
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_vm_size" {
  type    = string
  default = "Standard_B2s"
}
