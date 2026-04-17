# =============================================================================
# platform-bootstrap: installs the platform's cluster-wide building blocks
# on top of ANY Kubernetes cluster (kind, AKS, EKS, GKE, ...).
#
# Design rule: this module is PROVIDER-AGNOSTIC. It doesn't know or care
# whether the cluster is kind or AKS. The CALLER (envs/local or
# envs/azure-dev) wires up the `kubernetes`, `helm`, and `kubectl` providers
# with the right credentials and passes them in implicitly.
#
# Why this matters: it's THE interview talking point. The same module
# promoted from laptop to production means zero code changes between envs.
# =============================================================================

# Common labels we stamp on every namespace we create, so `kubectl get ns
# -l app.kubernetes.io/part-of=devops-platform` lists everything we own
# and distinguishes our infra from tenant namespaces.
locals {
  labels = {
    "app.kubernetes.io/part-of"    = "devops-platform"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Namespaces
# -----------------------------------------------------------------------------
# Why we create these explicitly and not via `helm_release.create_namespace`:
#  1) We want to set labels on the namespace (for NetworkPolicy matchers).
#  2) We want Terraform to own the namespace lifecycle (destroy cleans up).
#  3) Multiple Helm charts deploying into the same namespace would race each
#     other trying to create it.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name   = "ingress-nginx"
    labels = local.labels
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = merge(local.labels, {
      # Redundant with the auto-injected `kubernetes.io/metadata.name` label
      # k8s 1.22+ adds, but we set it explicitly so older NetworkPolicies
      # keep working. NetworkPolicy in charts/agent-integration references
      # this label to allow Prometheus to scrape tenant pods.
      "kubernetes.io/metadata.name" = "monitoring"
    })
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name   = "argocd"
    labels = local.labels
  }
}

# Sealed Secrets is optional: a cluster might use External Secrets + a cloud
# secret store instead. The count=0/1 idiom is how Terraform does conditional
# resources.
resource "kubernetes_namespace" "sealed_secrets" {
  count = var.enable_sealed_secrets ? 1 : 0
  metadata {
    name   = "sealed-secrets"
    labels = local.labels
  }
}

# -----------------------------------------------------------------------------
# Ingress controller (ingress-nginx)
# -----------------------------------------------------------------------------
# ingress-nginx is the most widely-used Ingress implementation. We run it
# differently depending on environment:
#   - kind:  NodePort + hostPort so it listens on the host's :80/:443 (the
#            kind control-plane node is mapped to localhost via extra_port_mappings).
#   - AKS:   LoadBalancer -> Azure provisions a real public LB automatically.
# -----------------------------------------------------------------------------

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  # Pin chart versions so `terraform apply` is reproducible. Never use
  # "latest" in IaC: a new chart release could silently change defaults.
  version = "4.11.3"
  timeout = 600  # seconds; 10 min covers image pulls on slow networks

  # `values` takes a list of YAML strings that Helm merges in order.
  # `yamlencode` converts an HCL map to YAML so we can keep the values
  # readable as native HCL.
  values = [yamlencode({
    controller = {
      service = {
        type = var.ingress_service_type
      }
      # --- kind-specific scheduling ---
      # On kind we pin ingress-nginx to the control-plane node (which we
      # labelled `ingress-ready=true` in the kind-cluster module) so
      # host-port binding hits the right container.
      nodeSelector = var.ingress_service_type == "NodePort" ? {
        "ingress-ready" = "true"
      } : {}
      # Default control-plane taints would prevent scheduling; tolerate.
      tolerations = var.ingress_service_type == "NodePort" ? [
        {
          key      = "node-role.kubernetes.io/control-plane"
          operator = "Equal"
          effect   = "NoSchedule"
        },
      ] : []
      # Bind 80/443 on the host, so kind's extra_port_mappings in the
      # cluster config forward curl localhost:80 into ingress-nginx.
      hostPort = var.ingress_service_type == "NodePort" ? {
        enabled = true
        ports = {
          http  = 80
          https = 443
        }
      } : { enabled = false }
      extraArgs = {
        # Enables SNI-based TLS pass-through (rarely needed but cheap to enable).
        "enable-ssl-passthrough" = ""
      }
      # Let Prometheus scrape ingress-nginx's own metrics (rps, connection
      # counts, latency histograms). The label release=kube-prometheus-stack
      # is how the operator picks up this ServiceMonitor.
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true, additionalLabels = { release = "kube-prometheus-stack" } }
      }
    }
  })]
}

# -----------------------------------------------------------------------------
# kube-prometheus-stack (Prometheus Operator + Prometheus + Alertmanager + Grafana)
# -----------------------------------------------------------------------------
# One chart gives us:
#  - Prometheus Operator (watches ServiceMonitor/PodMonitor CRDs)
#  - A Prometheus instance scraping everything with a ServiceMonitor
#  - Alertmanager (not wired to anything by default)
#  - Grafana with the standard Kubernetes dashboards pre-provisioned
#  - kube-state-metrics + node-exporter for cluster-level metrics
# This is a MASSIVE time-saver vs wiring each piece yourself.
# -----------------------------------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.5.0"
  timeout    = 900  # 15 min; this chart pulls a LOT of images

  values = [yamlencode({
    # Stable object name prefix. Default includes the release name which is
    # fine; we shorten it so `kubectl get svc` output is readable.
    fullnameOverride = "kps"

    prometheus = {
      prometheusSpec = {
        # By DEFAULT the operator only picks up ServiceMonitors with the
        # release label. Nil'ing these selectors makes Prometheus discover
        # any ServiceMonitor in any namespace. That's what lets tenant
        # Helm releases ship their own ServiceMonitor without touching
        # Prometheus config.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        # 7 days of metrics is plenty for a demo. Production uses
        # remote_write to long-term storage (Thanos, Mimir, Azure Monitor).
        retention = "7d"
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { cpu = "1", memory = "2Gi" }
        }
      }
    }

    grafana = {
      # Dev-only password. In prod: OIDC + adminUser disabled entirely.
      adminPassword = "admin"
      service       = { type = "ClusterIP" }
      ingress = {
        enabled          = true
        ingressClassName = "nginx"
        hosts            = ["grafana.local.test"]
      }
      defaultDashboardsTimezone = "browser"
    }

    alertmanager = { enabled = true }
  })]

  # Ingress controller must exist before Grafana's Ingress is created, or
  # the IngressClass won't resolve and the admission webhook can reject it.
  depends_on = [helm_release.ingress_nginx]
}

# -----------------------------------------------------------------------------
# Sealed Secrets (optional)
# -----------------------------------------------------------------------------
# Lets you commit ENCRYPTED secrets to Git. Workflow:
#   1) kubeseal CLI fetches the cluster's public key.
#   2) echo -n "value" | kubeseal creates a SealedSecret YAML (encrypted).
#   3) Commit that YAML to Git (safe).
#   4) Controller in-cluster decrypts it into a real Secret at apply time.
#
# Tradeoffs vs External Secrets Operator:
#   + Simpler; no cloud vault required.
#   - Secrets are tied to THIS cluster's private key (rotation is painful).
#   - Losing the controller's key = losing all your secrets.
# Prod path on Azure: External Secrets + Azure Key Vault + Workload Identity.
# -----------------------------------------------------------------------------

resource "helm_release" "sealed_secrets" {
  count      = var.enable_sealed_secrets ? 1 : 0
  name       = "sealed-secrets"
  namespace  = kubernetes_namespace.sealed_secrets[0].metadata[0].name
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = "2.16.1"
  timeout    = 600

  values = [yamlencode({
    fullnameOverride = "sealed-secrets-controller"
  })]
}

# -----------------------------------------------------------------------------
# Argo CD
# -----------------------------------------------------------------------------
# The GitOps controller: watches a Git repo, applies manifests to the
# cluster, reconciles any drift.
#
# Why Argo CD and not Flux:
#   - Argo has a nice web UI (matters for FDEs who aren't platform people).
#   - Argo's "Applications" map cleanly to our "one release per tenant" model.
#   - Flux's Kustomize-first approach is cleaner for pure-platform teams;
#     either is a defensible choice.
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.5"
  timeout    = 900

  values = [yamlencode({
    global = { domain = "argocd.local.test" }

    configs = {
      params = {
        # Argo CD's API server also terminates TLS by default; ingress-nginx
        # in front would make it double-TLS. "insecure" here means "don't
        # terminate TLS at argocd-server" - let ingress-nginx do it instead.
        "server.insecure" = true
      }
      # Optional password override. If empty, Argo generates a random one
      # stored in the `argocd-initial-admin-secret` Secret.
      secret = var.argocd_admin_password_bcrypt != "" ? {
        argocdServerAdminPassword = var.argocd_admin_password_bcrypt
      } : {}
    }

    server = {
      ingress = {
        enabled          = true
        ingressClassName = "nginx"
        hostname         = "argocd.local.test"
      }
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true, additionalLabels = { release = "kube-prometheus-stack" } }
      }
    }
    # Argo CD has three sub-controllers, each with its own metrics.
    controller = {
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true, additionalLabels = { release = "kube-prometheus-stack" } }
      }
    }
    repoServer = {
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true, additionalLabels = { release = "kube-prometheus-stack" } }
      }
    }
  })]

  depends_on = [
    # Ingress exists before Argo's Ingress gets admitted.
    helm_release.ingress_nginx,
    # Prometheus Operator CRDs must exist before ServiceMonitor objects.
    helm_release.kube_prometheus_stack,
  ]
}

# -----------------------------------------------------------------------------
# Root "app-of-apps" Application
# -----------------------------------------------------------------------------
# This is the handoff from Terraform to GitOps. Terraform creates ONE
# Argo CD Application that points at gitops/argocd/ in this repo. That
# directory contains more Application YAMLs (tenants, platform add-ons).
# Argo CD then syncs everything under that path.
#
# From this point on, Terraform is done. Day-2 operations are Git commits.
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "root_app" {
  # `kubectl_manifest` from alekc/kubectl applies arbitrary YAML. We use it
  # (instead of kubernetes_manifest) because it handles CRDs that don't
  # exist until the Argo CD chart finishes installing - kubernetes_manifest
  # tries to validate against the API server at PLAN time and fails for
  # not-yet-existing CRDs.
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      # The finalizer tells Argo CD to delete the child resources when this
      # Application is deleted (cascading cleanup). Without it, deleting the
      # Application leaves dangling Deployments behind.
      finalizers = [
        "resources-finalizer.argocd.argoproj.io",
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_repo_revision
        path           = var.gitops_app_of_apps_path
        # Recurse = pick up every file in the directory tree. Means we can
        # add a new tenant by dropping a YAML in gitops/argocd/tenants/
        # without editing any other file.
        directory = {
          recurse = true
        }
      }
      destination = {
        # `kubernetes.default.svc` is the in-cluster API server. Argo CD
        # deploys to its OWN cluster (the simple case). For multi-cluster
        # GitOps you'd register additional clusters and reference them here.
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        # automated.prune=true: if we delete a file from Git, Argo deletes
        # the corresponding resource. Without this, Git and cluster drift.
        # automated.selfHeal=true: if someone kubectl-edits a resource, Argo
        # reverts the change on next sync. This is the GitOps "source of
        # truth" enforcement.
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          # Create target namespaces if missing (tenant-acme etc.).
          "CreateNamespace=true",
          # Only re-apply manifests that have drifted; skip the rest. Faster
          # syncs on large repos.
          "ApplyOutOfSyncOnly=true",
        ]
      }
    }
  })

  # CRDs (Application, AppProject) only exist once the Argo CD chart is
  # fully installed.
  depends_on = [helm_release.argocd]
}
