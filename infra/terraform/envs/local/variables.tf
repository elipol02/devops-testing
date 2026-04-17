# Inputs for the local env. Set these via `-var` or a terraform.tfvars file.

variable "gitops_repo_url" {
  # Argo CD needs a PUBLIC HTTPS URL (or SSH + deploy key). For the demo,
  # set this to your fork's HTTPS URL: https://github.com/<you>/devops-platform.
  description = "HTTPS URL of the GitOps repo for Argo CD to track."
  type        = string
}

variable "gitops_repo_revision" {
  # Branch/tag/sha. `main` is fine for demo; tag in prod.
  description = "Branch Argo CD tracks."
  type        = string
  default     = "main"
}

variable "cluster_name" {
  # Flows into both the kind cluster name and the kubeconfig filename.
  type    = string
  default = "devops-platform"
}
