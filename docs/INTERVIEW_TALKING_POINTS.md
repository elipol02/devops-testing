# Interview talking points

Map of the job description's "Areas of ownership" to concrete artifacts in
this repo. Every bullet below has a file you can open in the interview.

## Areas of ownership

### Cloud infrastructure for hosting custom services

- Azure AKS module: [infra/terraform/modules/aks-cluster/main.tf](../infra/terraform/modules/aks-cluster/main.tf)
  - Workload Identity enabled, Container Insights via OMS agent, ACR pull via
    kubelet managed identity.
- Same `platform-bootstrap` module runs on both kind (laptop) and AKS
  (Azure), so every FDE gets an identical developer experience:
  [infra/terraform/modules/platform-bootstrap/main.tf](../infra/terraform/modules/platform-bootstrap/main.tf)

Talking point: "The platform-bootstrap module is provider-agnostic. The
caller wires providers; the module only knows about Kubernetes. That's what
lets me promote from kind to AKS without rewriting anything."

### Reusable CI/CD pipeline templates FDEs can adopt

- [.github/workflows/reusable-service.yml](../.github/workflows/reusable-service.yml) is a workflow_call library (~150 lines) that does lint,
  test, Trivy scan, build, push GHCR, and PR a tag bump in the GitOps repo.
- Adopting it for a new service is a ~15-line caller: [.github/workflows/agent-echo.yml](../.github/workflows/agent-echo.yml)

Talking point: "An FDE ships a new service by writing a caller workflow that
passes `service_path`, `image_name`, and a list of tenant values files to
bump. They don't touch CI internals."

### Champion Infrastructure as Code

- All Terraform: [infra/terraform/](../infra/terraform/)
- Three modules, two envs. Same chart + GitOps for kind and AKS.
- Module inputs are typed with validation blocks (see `ingress_service_type`
  variable).

Talking point: "Every infrastructure change is a Terraform `plan` in a PR,
reviewed, then `apply` on merge. I never touch the Azure portal."

### K8s for hosting many diverse integration services

- One reusable Helm chart: [charts/agent-integration/](../charts/agent-integration/)
- Isolation:
  - namespace-per-tenant
  - Default-deny `NetworkPolicy` with narrow allows:
    [charts/agent-integration/templates/networkpolicy.yaml](../charts/agent-integration/templates/networkpolicy.yaml)
  - `ResourceQuota`: [charts/agent-integration/templates/resourcequota.yaml](../charts/agent-integration/templates/resourcequota.yaml)
  - Non-root container with read-only root FS and dropped caps: [charts/agent-integration/values.yaml](../charts/agent-integration/values.yaml)

Talking point: "NetworkPolicy default-deny is the isolation floor. If I can't
explain why a pod can reach something, it shouldn't be able to."

### Monitoring and observability

- kube-prometheus-stack installed by the platform-bootstrap module.
- Every tenant gets a `ServiceMonitor` out of the box:
  [charts/agent-integration/templates/servicemonitor.yaml](../charts/agent-integration/templates/servicemonitor.yaml)
- Service-level metrics exposed at `/metrics`:
  [services/agent-echo/app/metrics.py](../services/agent-echo/app/metrics.py)
  (request counts, OpenRouter latency histogram, tokens).
- Structured JSON logs with tenant + request_id context:
  [services/agent-echo/app/logging_config.py](../services/agent-echo/app/logging_config.py)

Talking point: "An FDE gets tenant-labeled metrics and logs for free. They
don't remember to instrument. The chart does it."

### Primary DevOps partner for FDEs

- The self-service CLI: [platformctl/platformctl/cli.py](../platformctl/platformctl/cli.py)
  - `new-tenant`, `list-tenants`, `delete-tenant`, `lint`.
- CLI is deliberately a thin wrapper around Git + gh. No cluster creds.
  Runs from a laptop, CI, or a dev portal identically.

Talking point: "The CLI never talks to the cluster. Everything is Git.
Argo CD is the actor. This matters for audit, for reverts, and for letting a
CI job onboard a tenant without cluster access."

### Python / Go / Bash automation across the lifecycle

- Python: [platformctl/platformctl/cli.py](../platformctl/platformctl/cli.py) (Typer CLI)
- Bash: [scripts/bootstrap-local.sh](../scripts/bootstrap-local.sh), [scripts/bootstrap-azure.sh](../scripts/bootstrap-azure.sh), [scripts/seed-openrouter-secret.sh](../scripts/seed-openrouter-secret.sh), [scripts/smoke-test.sh](../scripts/smoke-test.sh)
- Go: intentionally skipped to keep the weekend realistic. I'd add a Go
  reconciler (Kubebuilder operator) to manage tenants as a CRD.

Talking point: "Honest scope call: I picked Python for the CLI because it
ships fastest. If tenant count grows past O(50) I'd replace the CLI with a
Tenant CRD + operator in Go so adding a tenant becomes a `kubectl apply`."

### Support and modernize legacy Azure infrastructure

- [docs/AZURE_DEMO_RUNBOOK.md](AZURE_DEMO_RUNBOOK.md) shows the lift: same
  chart, same GitOps repo, new Terraform env.
- [docs/NEXT_STEPS.md](NEXT_STEPS.md) describes the "VM -> AKS" story
  (ship a containerized version of the VM workload, pin it to a tenant
  namespace, strangler-fig traffic shift).

## Who you are

- "5+ years" -> I don't have 5 years of DevOps. I've shipped this weekend
  project end-to-end, I understand each tool well enough to defend my
  choices, and I can tell you what I haven't done yet.
- "Customer-first mindset" -> the CLI exists so FDEs don't file a ticket to
  get a tenant. The chart picks sensible defaults so FDEs don't have to
  learn NetworkPolicy.
- "Kubernetes / Helm / Docker" -> covered in the chart and runbook.
- "GitHub Actions + Argo CD" -> reusable-service.yml + app-of-apps.
- "Terraform" -> three modules, two envs, validation blocks, outputs.
- "Self-service tools / platforms" -> platformctl is the concrete artifact.

## Expected hard questions and answers

- "Why not a library chart?" -> One reusable chart is enough at this scope.
  Library charts are correct when you have 5+ services with shared primitives
  (database chart, worker chart, cronjob chart). I'd split at that point.
- "Why not Flux instead of Argo CD?" -> Either works. Argo CD has a better
  UI, which matters for FDEs (not just platform). Flux has cleaner
  multi-tenancy and Kustomize-first. I'd pick Flux if all consumers were
  platform engineers.
- "Why Sealed Secrets, not External Secrets?" -> Speed for a weekend demo.
  The chart's `existingSecret` knob means swapping is one PR.
- "How do you handle a bad tenant rollout?" -> Per-tenant Argo CD Application
  means a broken release is scoped. `git revert` is the rollback. The
  Deployment's `maxUnavailable: 0` keeps at least `replicaCount` serving.
- "How do tenants NOT reach each other?" -> default-deny NetworkPolicy +
  ResourceQuota + separate namespaces. Argo CD's AppProject scopes which
  namespaces a tenant app can touch.
- "Where's tracing?" -> Explicitly out of scope. The OTel collector would go
  in `platform-bootstrap`, and `agent-echo` would add
  `opentelemetry-instrumentation-fastapi`.

## 90-second elevator version

"I built a self-service platform where an FDE runs `platformctl new-tenant`,
which opens a PR. Merging the PR makes Argo CD sync a new Helm release of a
shared `agent-integration` chart into its own namespace with default-deny
NetworkPolicy, ResourceQuota, HPA, ServiceMonitor, and a non-root container.
The same Terraform modules stand the cluster up on kind for development and
AKS for real environments, with the platform add-ons installed by a
provider-agnostic bootstrap module. CI is a reusable workflow that any new
service adopts in 15 lines. The demo service calls OpenRouter, which stands
in for a real AI integration."
