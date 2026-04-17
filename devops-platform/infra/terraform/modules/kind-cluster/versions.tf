# Provider pins for kind-cluster.
#
# tehcyx/kind is the community kind provider (no official HashiCorp one
# exists). It shells out to `kind` - make sure `kind` is on PATH.
#
# hashicorp/local is used by some kind provider internals for writing the
# kubeconfig file.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
