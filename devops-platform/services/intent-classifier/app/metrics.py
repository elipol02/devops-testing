"""Prometheus metrics for intent-classifier.

Metric names use the `intent_classifier_` prefix - NOT `agent_echo_` - so
both services can land in the same Prometheus and be distinguished by
metric name (not just by label). That matches how Prometheus naming
conventions work: the metric name identifies what is being measured, labels
slice the dimensions.

Every platform service defines its own metrics. The ServiceMonitor in the
chart scrapes whatever is on /metrics; it's service-agnostic.
"""

from prometheus_client import CollectorRegistry, Counter, Histogram

registry = CollectorRegistry()

requests_total = Counter(
    "intent_classifier_requests_total",
    "Total requests handled by the intent-classifier service",
    labelnames=("endpoint", "status"),
    registry=registry,
)

classifications_total = Counter(
    "intent_classifier_classifications_total",
    "Total classifications produced, labelled by resolved intent",
    labelnames=("intent", "outcome"),
    registry=registry,
)

openrouter_latency_seconds = Histogram(
    "intent_classifier_openrouter_latency_seconds",
    "Latency of upstream OpenRouter calls in seconds",
    labelnames=("model", "outcome"),
    buckets=(0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0),
    registry=registry,
)

openrouter_tokens_total = Counter(
    "intent_classifier_openrouter_tokens_total",
    "Total tokens reported by OpenRouter responses",
    labelnames=("model", "kind"),
    registry=registry,
)
