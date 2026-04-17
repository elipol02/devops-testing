# agent-integration

A reusable Helm chart that describes the SHAPE of any per-tenant custom
integration service on this platform. Not a product. The same chart
deploys wildly different services - one tenant runs a chat echo,
another runs an intent classifier, a third runs whatever the next FDE
builds. The chart handles the infra-shaped bits; the service image
handles the business logic.

One release = one tenant.

## What the chart renders

| Resource        | Why it's there                                                     |
| --------------- | ------------------------------------------------------------------ |
| Deployment      | Runs the tenant's image; non-root, read-only root fs, dropped caps |
| Service         | ClusterIP :80 -> pod :8000                                         |
| Ingress         | Host-based routing via ingress-nginx                               |
| HPA (optional)  | Autoscale on CPU                                                   |
| ConfigMap       | Non-secret env vars (arbitrary KEY=VALUE, passed through to the pod) |
| Secret          | Either `existingSecret` (prod) or `createFromValues` (dev only)    |
| NetworkPolicy   | Default-deny + narrow allow (DNS + egress + ingress from ingress-nginx) |
| ResourceQuota   | Per-tenant blast-radius cap                                        |
| ServiceMonitor  | Prometheus Operator scrape rule (pointed at `/metrics`)            |

## Design invariants

- **Namespace-per-tenant.** The GitOps Application's `destination.namespace`
  is `tenant-<slug>`. The AppProject restricts tenants to that glob.
- **Service-agnostic.** No field in this chart is specific to `agent-echo`
  or `intent-classifier`. The `config:` map passes arbitrary keys through
  to the pod env; the service decides which ones it reads.
- **Default-deny NetworkPolicy** + a narrow allow list.
- **Non-root container** with a read-only root filesystem and dropped caps.
- **ServiceMonitor** makes Prometheus scrape `/metrics` automatically.
- **Secrets are NEVER inline in prod.** Set `secret.existingSecret` to
  a name managed by Sealed Secrets or External Secrets.

## Minimum override to add a tenant

```yaml
tenant: acme
environment: dev

# Pick whatever image this tenant runs. Different tenants pick different
# images. All that matters is that the image exposes /health, /ready,
# /metrics and binds :8000 - the chart's convention.
image:
  repository: ghcr.io/OWNER/agent-echo     # or intent-classifier, or ...
  tag: "0.1.0"

ingress:
  enabled: true
  className: nginx
  host: acme.local.test

secret:
  existingSecret: acme-agent-echo-secrets

# Service-specific env vars. The chart passes them through as a
# ConfigMap; the service decides which prefix (AGENT_ECHO_,
# INTENT_CLASSIFIER_, ...) it actually reads.
config:
  AGENT_ECHO_OPENROUTER_MODEL: "openrouter/auto"
```

## The service contract (what your image must do)

The chart assumes every service:

1. Binds HTTP on `:8000`.
2. Exposes `GET /health` (liveness) returning 200 when the process is up.
3. Exposes `GET /ready` (readiness) returning 200 when ready for traffic.
4. Exposes `GET /metrics` in Prometheus text format.
5. Runs as a non-root user (our Dockerfiles use UID 10001).

Anything else - what endpoints you expose under `/v1/*`, what env vars
you read, what libraries you use - is entirely up to the service.

## Render + dry-run

```bash
helm template acme . -f values.yaml --set tenant=acme | kubectl apply --dry-run=client -f -
```
