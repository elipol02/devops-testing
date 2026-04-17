# agent-echo

Sample per-tenant custom integration service. Stand-in for a real per-customer service deployed by the platform.

- `GET /health`: liveness probe (always 200 if the process is up)
- `GET /ready`: readiness probe (503 if `AGENT_ECHO_OPENROUTER_API_KEY` is missing)
- `GET /metrics`: Prometheus exposition
- `POST /v1/respond`: body `{"message": "...", "model": "optional override"}` -> calls OpenRouter

## Local dev

```bash
pip install -e ".[dev]"
export AGENT_ECHO_OPENROUTER_API_KEY=sk-or-...
uvicorn app.main:app --reload
```

Run tests:

```bash
pytest
```

## Configuration (env vars)

| Variable | Default | Notes |
| --- | --- | --- |
| `AGENT_ECHO_TENANT` | `unknown` | Customer/tenant identifier, baked into log context |
| `AGENT_ECHO_ENVIRONMENT` | `dev` | `dev|staging|prod` |
| `AGENT_ECHO_OPENROUTER_API_KEY` | (required) | Provided via a Kubernetes Secret in real deployments |
| `AGENT_ECHO_OPENROUTER_MODEL` | `openrouter/auto` | Override per tenant in Helm values |
| `AGENT_ECHO_SYSTEM_PROMPT` | (built-in) | Customizable per tenant |
| `AGENT_ECHO_LOG_LEVEL` | `INFO` | |
