# =============================================================================
# kind-cluster: spins up a single-node Kubernetes cluster inside Docker.
#
# What is kind: "Kubernetes IN Docker." Each cluster "node" is actually a
# Docker container running systemd + kubelet + the container runtime. The
# whole cluster is disposable - delete the container, cluster is gone.
#
# Why a single-node cluster for local dev:
#   - Faster to start (<30s).
#   - Lower RAM (one node ~1 GB vs 3x for multi-node).
#   - Identical API surface to a real cluster for everything we demo.
#
# The tricky part: getting external traffic (curl from your host) INTO the
# cluster. Kind doesn't provision cloud LoadBalancers. The pattern below
# (hostPort + ingress-ready label + extra_port_mappings) is the official
# kind recipe for running ingress-nginx locally.
# =============================================================================

resource "kind_cluster" "this" {
  name = var.cluster_name

  # Block `terraform apply` until the control-plane is Ready, so downstream
  # resources (Helm charts in platform-bootstrap) can talk to it immediately.
  wait_for_ready = true

  # pathexpand() resolves ~ -> $HOME, cross-platform. Lets us default the
  # kubeconfig to a tool-owned path that doesn't stomp on the user's
  # existing ~/.kube/config.
  kubeconfig_path = pathexpand(var.kubeconfig_path)

  kind_config {
    kind        = "Cluster"
    # kind's own config version - NOT a Kubernetes version. Kind docs pin
    # this to v1alpha4 at time of writing.
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      # One node only, acting as both control-plane and worker (kind's
      # default when you don't tolerate the control-plane taint).
      role = "control-plane"

      # kubeadm_config_patches: raw YAML merged into the kubeadm config kind
      # generates. Here we set a kubelet label that ingress-nginx targets
      # via its nodeSelector (see platform-bootstrap main.tf). Pattern is
      # straight from https://kind.sigs.k8s.io/docs/user/ingress/.
      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      # Port mappings from the host machine INTO the kind Docker container
      # that runs this node. Combined with ingress-nginx running hostPort
      # inside the pod, this forms a chain:
      #
      #   host:80 -> docker:80 -> node:80 -> ingress-nginx pod :80 -> Service
      #
      # Change `ingress_http_port` in variables.tf if port 80 on your host
      # is already taken (e.g. by IIS on Windows).
      extra_port_mappings {
        container_port = 80
        host_port      = var.ingress_http_port
        protocol       = "TCP"
      }

      extra_port_mappings {
        container_port = 443
        host_port      = var.ingress_https_port
        protocol       = "TCP"
      }
    }
  }
}
