# =============================================================================
# Outputs - the "public API" of this module.
#
# Callers (envs/local) use endpoint + certs to configure the `kubernetes`
# and `helm` providers WITHOUT reading the kubeconfig file (avoids a chicken
# -and-egg where the file might not exist yet at plan time).
# =============================================================================

output "cluster_name" {
  value = kind_cluster.this.name
}

output "kubeconfig_path" {
  # Path on the host filesystem. Useful for scripts: `export
  # KUBECONFIG=$(terraform output -raw kubeconfig_path)`.
  value = kind_cluster.this.kubeconfig_path
}

# API server endpoint (https://127.0.0.1:<random-port>). Changes every time
# you recreate the cluster.
output "endpoint" {
  value = kind_cluster.this.endpoint
}

# X.509 client cert + key used to authenticate to the API server.
# sensitive=true hides these from `terraform output` unless -raw is passed.
output "client_certificate" {
  value     = kind_cluster.this.client_certificate
  sensitive = true
}

output "client_key" {
  value     = kind_cluster.this.client_key
  sensitive = true
}

# Cluster's CA cert - client verifies the API server with this.
output "cluster_ca_certificate" {
  value     = kind_cluster.this.cluster_ca_certificate
  sensitive = true
}
