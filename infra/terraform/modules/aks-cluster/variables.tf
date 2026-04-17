# Inputs for the aks-cluster module. Defaults are tuned for a cheap,
# short-lived demo environment in West Europe.

variable "prefix" {
  # Name prefix for every Azure resource (RG, ACR, AKS, Log Analytics).
  # Azure resource names have varying constraints; see aks-cluster/main.tf
  # for the substr/replace gymnastics needed for globally-unique ACR names.
  description = "Resource name prefix. Azure-global names (ACR) get a random suffix."
  type        = string
  default     = "devopsplat"
}

variable "location" {
  # Azure region. All resources co-locate here for latency + billing
  # simplicity. Westeurope is cheap and has good feature parity.
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "node_count" {
  # 2 nodes minimum so we can demo rolling updates without dropping all
  # replicas.
  description = "Default node pool size."
  type        = number
  default     = 2
}

variable "node_vm_size" {
  # B-series are "burstable" - cheap baseline CPU with credit-based burst.
  # Standard_B2s: 2 vCPU, 4 GB RAM, ~$30/mo. Right-sized for the demo.
  # Production: D-series (consistent CPU) or E-series (memory-optimized).
  description = "VM size for nodes. B2s keeps cost low for a demo."
  type        = string
  default     = "Standard_B2s"
}

variable "kubernetes_version" {
  # Keep within AKS's supported window; bump as Azure deprecates versions.
  # `az aks get-versions --location <loc>` lists what's available.
  description = "AKS control plane version."
  type        = string
  default     = "1.30"
}

variable "tags" {
  # Tags show up in Azure Cost Management - essential for blaming/attributing
  # spend when a bunch of demo clusters live in one subscription.
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    "app.kubernetes.io/part-of" = "devops-platform"
    "managed-by"                = "terraform"
  }
}
