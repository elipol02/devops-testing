# Inputs for the kind-cluster module. Defaults are tuned for a laptop demo.

variable "cluster_name" {
  # `kind get clusters` uses this; must be DNS-safe.
  description = "Name of the kind cluster."
  type        = string
  default     = "devops-platform"
}

variable "kubeconfig_path" {
  # Kept separate from ~/.kube/config so creating/destroying the demo
  # cluster never clobbers the user's existing contexts.
  description = "Where to write the resulting kubeconfig file."
  type        = string
  default     = "~/.kube/devops-platform.kubeconfig"
}

variable "ingress_http_port" {
  # If port 80 is already in use on your host, pick something like 8080 and
  # hit http://acme.example.test:8080 in your browser. NOTE: names.tld:port
  # requires matching `/etc/hosts` entries or a wildcard DNS like .localtest.me.
  description = "Host port mapped to the ingress controller's HTTP port."
  type        = number
  default     = 80
}

variable "ingress_https_port" {
  description = "Host port mapped to the ingress controller's HTTPS port."
  type        = number
  default     = 443
}
