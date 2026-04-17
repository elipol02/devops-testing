# =============================================================================
# aks-cluster: provisions an Azure Kubernetes Service cluster + its
# supporting infrastructure (Resource Group, ACR, Log Analytics).
#
# This is the "cloud" counterpart to kind-cluster. The IMPORTANT design
# point: once this module has run, its outputs are shaped the same as
# kind-cluster's (kubeconfig + endpoint + certs), so platform-bootstrap can
# install on TOP of either one without caring which it is.
#
# Resources created here:
#   - Resource Group   (container for everything, cheap cleanup via `rg delete`)
#   - Log Analytics    (AKS diagnostic logs destination)
#   - Azure Container Registry (where CI pushes images)
#   - AKS cluster      (managed Kubernetes control plane + 1 nodepool)
#   - Role assignment  (AKS kubelet -> ACR pull permission)
# =============================================================================

# Random 5-char suffix to make globally-unique ACR names. ACR names MUST be
# globally unique across ALL of Azure. random_string persists in state so
# subsequent applies don't regenerate it (which would rename/destroy ACR).
resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# -----------------------------------------------------------------------------
# Resource Group: the container. Deleting this RG wipes EVERYTHING below it
# in one shot. Makes `terraform destroy` belt-and-braces safe for a demo
# environment. In prod, each concern (ACR shared across clusters, logging
# shared, etc.) typically lives in its OWN RG.
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

# -----------------------------------------------------------------------------
# Log Analytics Workspace: the destination for AKS diagnostic logs and
# Container Insights metrics. Billed per-GB-ingested. 30-day retention is
# the minimum on the PerGB2018 SKU.
#
# Why enable it: gives us "who deleted the pod" audit trails and the
# Container Insights UI for free. The ONLY bit of Azure-specific
# observability in this project; everything else routes through Prometheus.
# -----------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.prefix}-logs"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018" # the standard pay-as-you-go SKU
  retention_in_days   = 30
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Azure Container Registry (ACR): stores Docker images privately.
#
# Alternatives considered:
#   - GHCR (GitHub Container Registry): also used by this repo for CI
#     builds. GHCR is PUBLIC-free, but requires image pull secrets for
#     private images in AKS (extra moving part).
#   - ACR: private-free on Standard SKU, and AKS pulls from it with the
#     kubelet's own managed identity (no Secret object needed).
#
# We use BOTH in this project: CI pushes to GHCR (the canonical artifact),
# and optionally mirrors to ACR for the AKS demo. Production would pick one.
# -----------------------------------------------------------------------------
resource "azurerm_container_registry" "this" {
  # ACR names are globally unique across Azure, alphanumeric only, max 50
  # chars. The substr() + replace() dance makes "devops-platform-xyz12"
  # into "devopsplatformxyz12" (hyphens stripped, truncated).
  name                = substr(replace("${var.prefix}${random_string.suffix.result}", "-", ""), 0, 50)
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  # "Standard" SKU: $5/mo, 100GB storage, good for dev/demo.
  # "Basic" is cheaper but lacks zone redundancy.
  # "Premium" adds geo-replication, private endpoints, signing.
  sku = "Standard"
  # admin_enabled=false forces AAD-based auth (no shared passwords).
  # Admin creds are a classic "oops committed to Git" foot-gun.
  admin_enabled = false
  tags          = var.tags
}

# -----------------------------------------------------------------------------
# AKS Cluster: the managed Kubernetes control plane.
#
# Azure runs the masters (API server, etcd, scheduler, controller manager)
# for us behind a single endpoint. We provide the worker nodes (the
# default_node_pool below). Billing: control plane is free on Free tier; we
# pay for nodes + LB + egress.
# -----------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  # dns_prefix feeds into the API server's public FQDN:
  #   <prefix>-<hash>.hcp.<region>.azmk8s.io
  dns_prefix         = "${var.prefix}-aks"
  kubernetes_version = var.kubernetes_version
  # Free tier = no SLA on the API server. For prod use "Standard" for the
  # 99.95% SLA + higher etcd limits. Costs ~$75/mo per cluster.
  sku_tier = "Free"

  # --- OIDC + Workload Identity ---
  # oidc_issuer_enabled publishes a JWT issuer URL from the cluster; AAD
  # can then trust tokens issued by this cluster to authenticate to Azure
  # services. `workload_identity_enabled` installs the mutating webhook
  # that injects federation tokens into pods annotated with the right
  # service account.
  #
  # This is the MODERN way for pods to auth to Azure (Key Vault, Storage,
  # etc.) - replacing the old "pod identity" which was deprecated in 2022.
  # For a demo, it's cosmetic; it's here to show knowledge of the pattern.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  # RBAC (role-based access control). Default on modern AKS, but explicit
  # is better than implicit.
  role_based_access_control_enabled = true

  default_node_pool {
    name       = "system" # hosts system pods (CoreDNS, kube-proxy, etc.)
    node_count = var.node_count
    vm_size    = var.node_vm_size
    # 64 GB per node is comfortable for container images. 30 GB default
    # fills up fast if you pull heavy images (e.g. prometheus stack).
    os_disk_size_gb = 64
    # `only_critical_addons_enabled=true` taints the pool so only system
    # DaemonSets schedule there. We set false so tenants can also land here
    # (simpler one-pool setup; real prod has a dedicated user pool).
    only_critical_addons_enabled = false
    # Default is 30. Bumped because each tenant pod has envoy sidecars etc.
    # in a mature setup; here it's just breathing room.
    max_pods = 50
    # Surge upgrades: during a node-image upgrade, spin up 10% extra nodes
    # first, then drain and terminate the old ones. Avoids eviction storms.
    upgrade_settings {
      max_surge = "10%"
    }
  }

  network_profile {
    # "azure" CNI: pods get IPs directly from the VNet subnet - fewer
    # layers, slightly faster networking, higher IP consumption than
    # "kubenet" which NAT-masquerades pod traffic.
    network_plugin = "azure"
    # Azure Network Policy provider: enforces NetworkPolicy objects (our
    # chart's NetworkPolicy would otherwise be advisory). See
    # charts/agent-integration/templates/networkpolicy.yaml for the
    # policies we ship. Alternatives: "calico" (richer), "cilium" (best).
    network_policy = "azure"
    # "standard" SKU LB supports multiple public IPs, availability zones.
    # "basic" is deprecated.
    load_balancer_sku = "standard"
  }

  # SystemAssigned identity: Azure manages this cluster's AAD identity for
  # us. UserAssigned is the alternative when you want the same identity
  # across clusters (rare).
  identity {
    type = "SystemAssigned"
  }

  # oms_agent installs the Container Insights DaemonSet, which ships node
  # + container metrics/logs to the Log Analytics workspace above.
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }

  # azure_policy_enabled installs the Gatekeeper webhook with Azure's
  # built-in OPA policies (e.g. "disallow privileged containers"). Nice
  # defense-in-depth; zero-cost to toggle on.
  azure_policy_enabled = true

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Role assignment: AKS's kubelet identity -> AcrPull on our ACR.
#
# WITHOUT this, pulling from the ACR would fail with "unauthorized" - AKS
# nodes have no inherent permission on other Azure resources. With this,
# kubelet authenticates using its managed identity and pulls seamlessly.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "aks_acr_pull" {
  # `kubelet_identity[0]` is a SEPARATE identity from the cluster's main
  # identity - it's the one node agents use. Common mistake: granting
  # AcrPull to the cluster identity instead of the kubelet one.
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  # This flag tells Azure not to verify the principal exists in AAD at
  # plan time (the managed identity may not have propagated yet).
  skip_service_principal_aad_check = true
}
