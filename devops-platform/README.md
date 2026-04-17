# devops-platform

A self-service DevOps platform for hosting per-customer "integration services"
on Kubernetes. Each customer typically gets its own service (its own code,
its own image); the platform provides the shared machinery — Helm chart
shape, CI pipeline, GitOps wiring, cluster add-ons, observability — so every
service looks the same from the outside.

> One command onboards a new customer onto any service. CI ships the code.
> Argo CD deploys it. Prometheus watches it. Same stack on a laptop and on
> Azure AKS.

## Mental model

- **Many services, one platform.** This repo ships two example services
  (`services/agent-echo`, `services/intent-classifier`) that look like what
  an FDE would build per customer. Adding a third is "copy one of them,
  rewrite the business logic". The chart / CI / GitOps machinery doesn't
  change.
- **Many tenants, one service each.** Each tenant (`acme`, `globex`, ...)
  runs exactly one service. Which one is the tenant's choice, encoded in
  `gitops/argocd/tenants/<tenant>.yaml`.

| Tenant   | Service             | Image                                 |
| -------- | ------------------- | ------------------------------------- |
| `acme`   | `agent-echo`        | `ghcr.io/<org>/agent-echo`            |
| `globex` | `intent-classifier` | `ghcr.io/<org>/intent-classifier`     |

## The 60-second tour

```text
  platformctl new-tenant --name initech --service intent-classifier
                              |
                              v
                 PR to the GitOps repo (this repo)
                              |
               merge -->  Argo CD syncs -->  new namespace tenant-initech
                                               +--- Deployment (intent-classifier)
                                               +--- Service + Ingress
                                               +--- ServiceMonitor (Prom scrape)
                                               +--- NetworkPolicy (default-deny)
                                               +--- ResourceQuota
```

Meanwhile, each service has its own independent pipeline:

```text
services/agent-echo/**          services/intent-classifier/**
          |                               |
          v                               v
 .github/workflows/             .github/workflows/
  agent-echo.yml                 intent-classifier.yml
          |                               |
          +--- lint / pytest / trivy / build / push GHCR
          |                               |
          v                               v
 PR bumping image tag           PR bumping image tag
 in acme.yaml ONLY              in globex.yaml ONLY
          |                               |
          +--- merge -> Argo CD rolls only that tenant's Deployment
```

## What's in the repo

| Path | What it is |
| --- | --- |
| [services/agent-echo/](services/agent-echo/) | Example service #1: wraps OpenRouter chat completion. |
| [services/intent-classifier/](services/intent-classifier/) | Example service #2: utterance -> fixed intent label. Different endpoint, different metrics, same operational shape. |
| [charts/agent-integration/](charts/agent-integration/) | Reusable Helm chart (the SHAPE). One release per tenant. Service-agnostic. |
| [infra/terraform/modules/](infra/terraform/modules/) | `kind-cluster`, `aks-cluster`, `platform-bootstrap` |
| [infra/terraform/envs/](infra/terraform/envs/) | `local` (kind) and `azure-dev` (AKS) |
| [gitops/argocd/](gitops/argocd/) | Root app-of-apps, tenants directory, project definitions |
| [platformctl/](platformctl/) | Python Typer CLI: `new-tenant --service ...`, `new-service`, `list-tenants`, `list-services`, `delete-tenant`, `lint` |
| [.github/workflows/](.github/workflows/) | Reusable CI + per-service callers + Terraform validate/plan |
| [scripts/](scripts/) | Bash helpers: bootstrap local, bootstrap Azure, seed secrets, smoke test |
| [docs/](docs/) | Architecture, runbooks, next steps |

## How to run it

- First time: [docs/INSTALL_PREREQS.md](docs/INSTALL_PREREQS.md) (Windows + WSL)
- Local (kind): [docs/LOCAL_DEMO_RUNBOOK.md](docs/LOCAL_DEMO_RUNBOOK.md)
- Azure (AKS): [docs/AZURE_DEMO_RUNBOOK.md](docs/AZURE_DEMO_RUNBOOK.md)
- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- What a real system adds on top: [docs/NEXT_STEPS.md](docs/NEXT_STEPS.md)

## Adding a new customer integration

Real-world flow an FDE would follow:

```bash
# 1. Scaffold a new service from the smallest existing template.
platformctl new-service --name churn-scorer --from intent-classifier

# 2. Edit services/churn-scorer/app/main.py to implement the new endpoint.

# 3. Copy the caller workflow.
cp .github/workflows/intent-classifier.yml .github/workflows/churn-scorer.yml
#    Update service_name / image_name / gitops_values_paths.

# 4. Onboard a tenant that runs it.
platformctl new-tenant --name initech --service churn-scorer
```

## Non-goals and trade-offs

Documented so the demo isn't misleading.

- No service mesh. `NetworkPolicy` is enough for isolation at this scope.
- No tracing yet; services are ready for OTel but the collector isn't installed.
- Sealed Secrets locally; Azure Key Vault via External Secrets is the
  upgrade path, documented but not implemented.
- No shared library between services (each service carries its own
  `logging_config.py`, `metrics.py`). In production you'd factor these
  into `libs/obs-py/`. Kept self-contained here so each service reads
  top-to-bottom without chasing imports.
- No Go code; the CLI is Python. Would be a Kubebuilder operator at scale.

Full "what I'd do with another week" list: [docs/NEXT_STEPS.md](docs/NEXT_STEPS.md)

## Replace these placeholders before first run

Search the repo for `YOUR-USER` and replace with your GitHub username:

- [gitops/argocd/tenants/acme.yaml](gitops/argocd/tenants/acme.yaml)
- [gitops/argocd/tenants/globex.yaml](gitops/argocd/tenants/globex.yaml)
- [platformctl/platformctl/cli.py](platformctl/platformctl/cli.py) (defaults; can also be overridden via flags)
- [.github/CODEOWNERS](.github/CODEOWNERS)

`infra/terraform/envs/local/terraform.tfvars` (copy from `.example`) expects
the HTTPS URL to your fork.
