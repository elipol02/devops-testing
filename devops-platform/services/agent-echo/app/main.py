"""FastAPI app entrypoint for agent-echo.

Endpoints:
    GET  /health   - liveness probe (cheap, no deps)
    GET  /ready    - readiness probe (checks OpenRouter API key present)
    GET  /metrics  - Prometheus text format (scraped by ServiceMonitor)
    POST /v1/respond - the actual "AI" endpoint; wraps OpenRouter chat completion

Design choices:
    * FastAPI over Flask: native async, OpenAPI schema free, pydantic
      validation. Matches the Python-async job description exactly.
    * structlog over stdlib logging: produces JSON out of the box, binds
      request-scoped context (request_id, tenant, path) automatically.
    * Prometheus client directly, no framework wrapper: a few counters cover
      the gold signals (requests, errors) without extra deps.
"""

from __future__ import annotations

import uuid
from contextlib import asynccontextmanager
from typing import Any

import structlog
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from app.config import settings
from app.logging_config import configure_logging, get_logger
from app.metrics import registry, requests_total
from app.openrouter import OpenRouterError, chat_completion


# ---- Request/response schemas ------------------------------------------------
# Using pydantic BaseModel gives us:
#   - automatic 422 on malformed JSON / missing fields
#   - OpenAPI schema at /docs without extra code
#   - one source of truth for validation + docs + typing


class RespondRequest(BaseModel):
    # min_length=1 rejects empty strings (FastAPI returns 422). max_length
    # caps payload size so a malicious client can't DoS us by sending a
    # 100 MB prompt that we then forward to the LLM.
    message: str = Field(..., min_length=1, max_length=4000)
    # Optional per-request model override - handy for a tenant wanting to
    # test a new model without a deploy.
    model: str | None = Field(default=None, description="Override the configured model")


class RespondResponse(BaseModel):
    reply: str
    model: str
    tenant: str
    request_id: str
    # OpenRouter returns token counts for billing observability. We pass
    # them through so Grafana dashboards can plot cost per tenant.
    usage: dict[str, Any] | None = None


# ---- Lifespan ---------------------------------------------------------------
# The `lifespan` context replaces the deprecated @app.on_event hooks. Code
# before `yield` runs at startup, code after at shutdown. We use it to
# configure logging ONCE (not per-request) and to emit structured startup
# logs that SREs can grep for.
@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging()
    log = get_logger(__name__)
    log.info("startup", model=settings.openrouter_model)
    yield
    log.info("shutdown")


app = FastAPI(
    title="agent-echo",
    version="0.1.0",
    description="DevOps platform demo: a per-tenant AI integration service.",
    lifespan=lifespan,
)


# ---- Middleware: per-request context + metrics ------------------------------
# Runs for EVERY request. Adds:
#   * A request_id (propagate an existing x-request-id header if provided,
#     else generate a UUID). This lets an SRE trace one user request across
#     ingress-nginx, this service, and OpenRouter.
#   * Structlog contextvars so every log line within this request carries
#     request_id/path/method without having to pass the logger around.
#   * A Prometheus counter increment with status-code label. Error-rate
#     alerts filter on status!~"2.."
@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    # clear_contextvars before bind = don't leak context from a previous
    # request handled on this same worker. Subtle but important.
    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(
        request_id=request_id,
        path=request.url.path,
        method=request.method,
    )
    log = get_logger("http")
    try:
        response = await call_next(request)
    except Exception:
        # log.exception adds stacktrace to the JSON log. We return a SAFE
        # error body (no traceback, no internals) to the client.
        log.exception("unhandled_error")
        requests_total.labels(endpoint=request.url.path, status="500").inc()
        return JSONResponse({"detail": "internal error", "request_id": request_id}, status_code=500)
    response.headers["x-request-id"] = request_id
    requests_total.labels(endpoint=request.url.path, status=str(response.status_code)).inc()
    log.info("request", status=response.status_code)
    return response


# ---- Infra endpoints --------------------------------------------------------


@app.get("/health", tags=["infra"])
def health() -> dict[str, str]:
    """Liveness probe: returns 200 as long as the process is up.

    Intentionally trivial - must NOT depend on OpenRouter. Kubernetes will
    restart the pod on a failing liveness; we only want that for "the
    Python process is wedged", not "OpenRouter is flaky."
    """
    return {"status": "ok"}


@app.get("/ready", tags=["infra"])
def ready() -> dict[str, str]:
    """Readiness probe: returns 503 if critical config is missing.

    K8s stops routing traffic here but does NOT kill the pod. This is the
    right place to surface "not yet ready to serve" conditions - missing
    config, unreachable upstream, etc.
    """
    if not settings.openrouter_api_key:
        raise HTTPException(status_code=503, detail="openrouter api key not configured")
    return {"status": "ready"}


@app.get("/metrics", tags=["infra"], include_in_schema=False)
def metrics() -> Response:
    # include_in_schema=False -> hide from /docs. Metrics aren't API; they
    # shouldn't clutter the customer-facing schema.
    # Prometheus text exposition format; CONTENT_TYPE_LATEST ensures the
    # right content-type for the server to parse ("text/plain; version=0.0.4").
    return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)


# ---- Business endpoint ------------------------------------------------------


@app.post("/v1/respond", response_model=RespondResponse, tags=["agent"])
async def respond(req: RespondRequest, request: Request) -> RespondResponse:
    """Call OpenRouter with the user's message, return the model's reply.

    Error mapping:
        - OpenRouterError (network/HTTP error upstream) -> 502 Bad Gateway.
          502 (not 500) tells the caller "we're fine; OUR dependency broke."
        - Missing choices in response -> 502 (the API lied to us).
    """
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    try:
        body = await chat_completion(req.message, model=req.model)
    except OpenRouterError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    choices = body.get("choices") or []
    if not choices:
        raise HTTPException(status_code=502, detail="OpenRouter returned no choices")

    reply = choices[0].get("message", {}).get("content", "")
    return RespondResponse(
        reply=reply,
        model=body.get("model", req.model or settings.openrouter_model),
        tenant=settings.tenant,
        request_id=request_id,
        usage=body.get("usage"),
    )
