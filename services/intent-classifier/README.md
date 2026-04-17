# intent-classifier

Second example per-tenant integration service. Exists to prove the
platform's core claim: one chart, one CI pipeline, one GitOps workflow,
*many* different services.

## What it does

Takes an utterance, asks an LLM (via OpenRouter) to classify it into ONE
of a configured set of intent labels, returns the label plus a `confident`
flag indicating whether the model's answer was in the allowed set.

## Why a separate service (not a route inside `agent-echo`)

Each customer integration an FDE builds is its own artifact:

- its own image (`ghcr.io/<org>/intent-classifier`, not `agent-echo`)
- its own CI pipeline (`.github/workflows/intent-classifier.yml`)
- its own code with its own dependencies, metrics, config surface
- its own release cadence

What they *share* with every other service in the platform:

- The chart at `charts/agent-integration/` (a generic
  "HTTP service + Prometheus + Ingress + NetworkPolicy" shape)
- The reusable CI workflow at `.github/workflows/reusable-service.yml`
- The Argo CD `AppProject` that scopes where they can deploy
- The bootstrapped cluster add-ons (ingress, Prometheus, Argo CD)
- Logging / metrics / secret-delivery conventions

## Endpoints

| Path            | Purpose                              |
| --------------- | ------------------------------------ |
| `GET  /health`  | Liveness (process up)                |
| `GET  /ready`   | Readiness (api key present)          |
| `GET  /metrics` | Prometheus scrape (`intent_classifier_*`) |
| `POST /v1/classify` | `{ "utterance": "..." }` -> `{ "intent": "...", "confident": true/false, ... }` |

## Config

All env vars use the `INTENT_CLASSIFIER_` prefix. See `app/config.py`.
Of particular note: `INTENT_CLASSIFIER_INTENTS` is a comma-separated list
that tenants override to match their own business domain.

## Local run

```bash
cd services/intent-classifier
pip install -e .[dev]
INTENT_CLASSIFIER_OPENROUTER_API_KEY=sk-... uvicorn app.main:app --reload
curl -X POST localhost:8000/v1/classify \
  -H 'content-type: application/json' \
  -d '{"utterance": "I want to cancel my plan"}'
```
