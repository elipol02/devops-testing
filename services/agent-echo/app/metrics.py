"""Prometheus metric definitions.

Naming convention: `agent_echo_<name>_<unit>_<suffix>` where suffix is one of
`total` (counter) or `seconds`/`bytes`/...(histogram). Prometheus best practice
documented at https://prometheus.io/docs/practices/naming/.

Why a private CollectorRegistry (not the default prometheus_client global):
    * Isolates our metrics from anything a library might inadvertently
      register on the default registry.
    * Lets the /metrics endpoint emit ONLY our metrics - cleaner output.
"""

from prometheus_client import CollectorRegistry, Counter, Histogram

registry = CollectorRegistry()

# Counter = monotonically increasing. Use with rate() in PromQL for req/s.
# Labels chosen for cardinality control: endpoint is bounded by the number
# of routes; status is a 3-digit int. Adding e.g. request_id as a label
# would blow up cardinality (one time series per request = OOM Prometheus).
requests_total = Counter(
    "agent_echo_requests_total",
    "Total requests handled by the agent-echo service",
    labelnames=("endpoint", "status"),
    registry=registry,
)

# Histogram: exposes a set of buckets ("count observations <= X"). Lets us
# compute p50/p95/p99 latency with histogram_quantile() in PromQL.
# Bucket choice: log-ish spacing from 100ms to 30s - appropriate for an LLM
# call which has a wide latency distribution. Default buckets (from ~5ms to
# 10s) would have empty high buckets for slower models.
openrouter_latency_seconds = Histogram(
    "agent_echo_openrouter_latency_seconds",
    "Latency of upstream OpenRouter calls in seconds",
    labelnames=("model", "outcome"),
    buckets=(0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0),
    registry=registry,
)

# Counter for token usage. `kind` is "prompt" / "completion" / "total" so
# Grafana can plot spend per model per tenant (cost per 1k tokens varies
# by model; join this metric with a cost-config lookup in Grafana).
openrouter_tokens_total = Counter(
    "agent_echo_openrouter_tokens_total",
    "Total tokens reported by OpenRouter responses",
    labelnames=("model", "kind"),
    registry=registry,
)
