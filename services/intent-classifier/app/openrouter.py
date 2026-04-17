"""Thin OpenRouter client for intent-classifier.

Differences from services/agent-echo/app/openrouter.py:
    * Different system prompt - this one constrains the LLM to output ONE of
      a fixed set of intent labels. That constraint is what turns a general
      chat model into a classifier.
    * Different X-Title (for OpenRouter's attribution) and error prefix
      naming.

Same observability shape (latency histogram + token counter) so the
shared chart/dashboards just work.
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
    """Raised for any failure calling OpenRouter."""


def _build_system_prompt(intents: list[str]) -> str:
    # We ask the model to answer with a single token. Cheap + easy to parse
    # + bounded output length. Real systems would use structured output /
    # function calling; this is enough to demo.
    joined = ", ".join(intents)
    return (
        "You are an intent classifier. Read the user's utterance and respond "
        f"with EXACTLY one label from this set: {joined}. "
        "Respond with only the label, no punctuation, no explanation. "
        "If none fit, respond with 'unknown'."
    )


async def classify(utterance: str, *, model: str | None = None) -> dict[str, Any]:
    """Ask OpenRouter to classify `utterance` into one of settings.intent_list.

    Returns the raw body (caller parses the label out). Records metrics on
    every outcome.
    """
    if not settings.openrouter_api_key:
        raise OpenRouterError("INTENT_CLASSIFIER_OPENROUTER_API_KEY is not configured")

    chosen_model = model or settings.openrouter_model
    url = f"{settings.openrouter_base_url.rstrip('/')}/chat/completions"
    payload = {
        "model": chosen_model,
        "messages": [
            {"role": "system", "content": _build_system_prompt(settings.intent_list)},
            {"role": "user", "content": utterance},
        ],
        # Cap tokens hard: we only want a single label back. Saves cost and
        # protects against prompt-injection attempts that try to make the
        # model monologue.
        "max_tokens": 8,
        # Deterministic-ish: low temperature = consistent labels for the
        # same input. A classifier that flips labels on identical input is
        # a bad classifier.
        "temperature": 0.0,
    }
    headers = {
        "Authorization": f"Bearer {settings.openrouter_api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/devops-platform-demo",
        "X-Title": f"intent-classifier/{settings.tenant}",
    }

    started = time.perf_counter()
    outcome = "ok"
    try:
        async with httpx.AsyncClient(timeout=settings.openrouter_timeout_seconds) as client:
            response = await client.post(url, json=payload, headers=headers)
            response.raise_for_status()
            body = response.json()
    except httpx.HTTPStatusError as exc:
        outcome = f"http_{exc.response.status_code}"
        log.warning("openrouter_http_error", status=exc.response.status_code, body=exc.response.text)
        raise OpenRouterError(f"OpenRouter HTTP {exc.response.status_code}") from exc
    except httpx.HTTPError as exc:
        outcome = "transport_error"
        log.warning("openrouter_transport_error", error=str(exc))
        raise OpenRouterError(str(exc)) from exc
    finally:
        elapsed = time.perf_counter() - started
        openrouter_latency_seconds.labels(model=chosen_model, outcome=outcome).observe(elapsed)

    usage = body.get("usage") or {}
    for kind in ("prompt_tokens", "completion_tokens", "total_tokens"):
        if (value := usage.get(kind)) is not None:
            openrouter_tokens_total.labels(model=chosen_model, kind=kind).inc(value)

    return body
