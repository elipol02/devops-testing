# =============================================================================
# Inputs for the platform-bootstrap module.
#
# These are the KNOBS the caller (envs/local or envs/azure-dev) sets to
# customize platform behavior per environment. Anything NOT here is the
# same across environments by design - that's what makes this module the
# "one shape of platform everywhere" primitive.
# =============================================================================

variable "gitops_repo_url" {
  description = "HTTPS URL of the GitOps repo Argo CD should track. Argo's root Application reads from here."
  type        = string
}

variable "gitops_repo_revision" {
  # A branch is convenient for a demo; production should pin a TAG or SHA
  # and promote by updating the tag reference in Terraform. Otherwise "main"
  # being force-pushed is the entire cluster's fate.
  description = "Branch / tag / sha Argo CD's app-of-apps tracks. Use a tag in prod for stable promotions."
  type        = string
  default     = "main"
}

variable "gitops_app_of_apps_path" {
  description = "Path within the GitOps repo to the app-of-apps directory (contains child Applications)."
  type        = string
  default     = "gitops/argocd"
}

variable "ingress_service_type" {
  # kind: "NodePort" + hostPort is the only way to reach ingress from the
  #       host machine (kind doesn't provision cloud LBs).
  # AKS/EKS/GKE: "LoadBalancer" triggers the cloud controller to create a
  #       real load balancer automatically.
  description = "Service type for ingress-nginx. 'NodePort' is correct for kind, 'LoadBalancer' for AKS."
  type        = string
  default     = "NodePort"
  # Validation runs at plan time - fail fast on typos (e.g. "loadbalancer"
  # lowercase is invalid and would silently fall through the helm values).
  validation {
    condition     = contains(["NodePort", "LoadBalancer", "ClusterIP"], var.ingress_service_type)
    error_message = "ingress_service_type must be NodePort, LoadBalancer, or ClusterIP."
  }
}

variable "enable_sealed_secrets" {
  # Set false on AKS when you use External Secrets + Azure Key Vault instead.
  description = "Whether to install the Sealed Secrets controller."
  type        = bool
  default     = true
}

variable "argocd_admin_password_bcrypt" {
  # sensitive=true hides the value from `terraform plan` output and state
  # diffs in the console. Doesn't encrypt state - still use a remote backend
  # with encryption (Azure Storage + SSE, S3 + KMS, etc.).
  description = "Optional: bcrypt hash of the Argo CD admin password. If empty, uses the auto-generated one (read with kubectl)."
  type        = string
  default     = ""
  sensitive   = true
}
