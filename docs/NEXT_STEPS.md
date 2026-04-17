# Next steps (the "what I'd do with another week")

Honest gaps to name in the interview, in priority order.

## 1. Secrets: External Secrets + Key Vault on Azure, SOPS locally

- Install External Secrets Operator in `platform-bootstrap`.
- Use Workload Identity (already enabled on AKS) so the ESO pod authenticates
  to Key Vault without a secret.
- Chart already supports `existingSecret`, so tenant values just change from
  `acme-agent-echo-secrets` (Sealed) to an `ExternalSecret` that materializes
  the same name.

## 2. Tenant as a CRD + Go operator

- Kubebuilder scaffold: `kind: Tenant` with fields `name`, `env`, `model`,
  `imageTag`, `quota`.
- Operator reconciles by creating the Argo CD Application on its behalf.
- `platformctl new-tenant` becomes `kubectl apply -f tenant.yaml` (or a thin
  CLI that emits that).
- Covers the "Go" bullet and the "reconciliation" pattern.

## 3. Observability: tracing

- Install OpenTelemetry Collector in `platform-bootstrap`.
- Add `opentelemetry-instrumentation-fastapi` to `agent-echo`.
- Ship traces to Tempo (self-hosted) or Azure Monitor Application Insights on
  AKS.

## 4. SSO for Argo CD and Grafana

- Azure AD OIDC on both. Argo CD already supports it via `configs.cm.oidc`.

## 5. Policy-as-code

- Install Kyverno or Gatekeeper.
- Required policies:
  - No `:latest` image tags in tenant namespaces.
  - No privileged containers.
  - Every Deployment must have resource limits.
  - Every tenant namespace must have a NetworkPolicy.

## 6. Cost controls

- Install Kubecost in `platform-bootstrap`.
- Add a `tenant` label-based dashboard so FDEs see their own spend.

## 7. Legacy Azure VM -> AKS strangler fig

For the "modernize legacy Azure infrastructure" JD bullet:

1. Containerize the VM workload (one Dockerfile, one Helm values override).
2. Deploy it as a second tenant on AKS alongside the new service.
3. Put both behind the same ingress; use header-based routing or a percentage
   split to shift traffic.
4. Once traffic is 100% on AKS, decommission the VM with Terraform.

## 8. Multi-cluster

- Argo CD on a management cluster managing N runtime clusters.
- Per-env runtime clusters (`dev`, `staging`, `prod`) wired via cluster
  secrets.
- Today's single-cluster design already works; the GitOps repo just grows an
  `env-prod/` directory.

## 9. Pre-commit and supply-chain

- `cosign` sign the image in CI, verify at admission with a Kyverno policy.
- `syft` SBOM upload to GitHub.
- pre-commit with ruff, terraform fmt, helm lint.
