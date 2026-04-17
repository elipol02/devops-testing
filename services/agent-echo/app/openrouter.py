"""Thin OpenRouter client.

Keeping this tiny and dependency-free (just httpx) so it's obvious what goes
over the wire. A real service would use the official SDK, retries, circuit
breakers, outbound request signing, etc.

Why a custom wrapper rather than OpenAI/langchain clients:
    * Trivial: the OpenRouter /chat/completions endpoint is OpenAI-compatible.
    * No hidden magic - useful in an interview where you might get grilled
      on "what does this actually send?"
    * One place to attach metrics/logs for every outbound call.
"""

from __future__ import annotations

import time
from typing import Any

import httpx

from app.config import settings
from app.logging_config import get_logger
from app.metrics import openrouter_latency_seconds, openrouter_tokens_total

log = get_logger(__name__)


class OpenRouterError(RuntimeError):
    """Raised for ANY failure calling OpenRouter (HTTP 4xx/5xx, timeouts,
    DNS, missing key). Callers translate to HTTP 502 - semantically "we're
    fine, our dependency broke."
    """


async def chat_completion(user_message: str, *, model: str | None = None) -> dict[str, Any]:
    """Call OpenRouter's chat completions endpoint. Returns the parsed JSON body.

    Records Prometheus metrics for latency and token usage regardless of outcome.
    """
    # Fail fast if not configured. We could rely on OpenRouter to 401, but
    # that would cost a round trip. The /ready probe already checks this
    # flag so pods without the key aren't routed traffic.
    if not settings.openrouter_api_key:
        raise OpenRouterError("AGENT_ECHO_OPENROUTER_API_KEY is not configured")

    # Per-request model override > global config > library default.
    chosen_model = model or settings.openrouter_model
    url = f"{settings.openrouter_base_url.rstrip('/')}/chat/completions"
    payload = {
        "model": chosen_model,
        "messages": [
            # System prompt establishes persona/guardrails. Configured via
            # env (ConfigMap) so tenants tune tone without code changes.
            {"role": "system", "content": settings.system_prompt},
            {"role": "user", "content": user_message},
        ],
    }
    headers = {
        "Authorization": f"Bearer {settings.openrouter_api_key}",
        "Content-Type": "application/json",
        # OpenRouter asks for these to attribute traffic for rate-limit tiers.
        # Public; not secrets.
        "HTTP-Referer": "https://github.com/devops-platform-demo",
        "X-Title": f"agent-echo/{settings.tenant}",
    }

    # perf_counter is monotonic, immune to wall-clock changes (NTP step).
    # Always use it (not time.time()) for latency measurement.
    started = time.perf_counter()
    outcome = "ok"
    try:
        # AsyncClient as a context manager = proper connection cleanup on
        # both success and exception paths. Timeout is per-request (not
        # per-connect); we set it to settings.openrouter_timeout_seconds
        # so a hung LLM doesn't pin an asyncio worker forever.
        async with httpx.AsyncClient(timeout=settings.openrouter_timeout_seconds) as client:
            response = await client.post(url, json=payload, headers=headers)
            # raise_for_status raises HTTPStatusError on 4xx/5xx. We catch
            # separately from HTTPError to grab the status code for metrics.
            response.raise_for_status()
            body = response.json()
    except httpx.HTTPStatusError as exc:
        # outcome labels end up in the histogram, so we can graph "ok vs
        # http_429 vs http_500" without having to break out a separate
        # counter.
        outcome = f"http_{exc.response.status_code}"
        log.warning("openrouter_http_error", status=exc.response.status_code, body=exc.response.text)
        raise OpenRouterError(f"OpenRouter HTTP {exc.response.status_code}") from exc
    except httpx.HTTPError as exc:
        # DNS fail, connection refused, timeout all land here.
        outcome = "transport_error"
        log.warning("openrouter_transport_error", error=str(exc))
        raise OpenRouterError(str(exc)) from exc
    finally:
        # ALWAYS record latency, even on failure. Otherwise a spike of
        # errors looks like "no traffic at all" in the dashboard.
        elapsed = time.perf_counter() - started
        openrouter_latency_seconds.labels(model=chosen_model, outcome=outcome).observe(elapsed)

    # Extract token usage from the response; OpenRouter uses the OpenAI
    # shape (`usage.prompt_tokens`, etc). Gracefully skip fields that are
    # missing from older/weirder model responses.
    usage = body.get("usage") or {}
    for kind in ("prompt_tokens", "completion_tokens", "total_tokens"):
        if (value := usage.get(kind)) is not None:
            openrouter_tokens_total.labels(model=chosen_model, kind=kind).inc(value)

    return body
