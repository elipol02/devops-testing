"""FastAPI app entrypoint for intent-classifier.

Endpoints:
    GET  /health        - liveness probe (cheap, no deps)
    GET  /ready         - readiness probe (checks OpenRouter API key present)
    GET  /metrics       - Prometheus text format (scraped by ServiceMonitor)
    POST /v1/classify   - the business endpoint: utterance -> intent label

This service exists to prove that one chart / one CI pipeline / one
GitOps workflow handles MULTIPLE different services at once. Compare
services/agent-echo/app/main.py to see the difference in domain logic
versus the identical operational surface (probes, metrics, middleware).
"""

from __future__ import annotations

import uuid
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from app.config import settings
from app.logging_config import configure_logging, get_logger
from app.metrics import classifications_total, registry, requests_total
from app.openrouter import OpenRouterError, classify


class ClassifyRequest(BaseModel):
    utterance: str = Field(..., min_length=1, max_length=2000)
    model: str | None = Field(default=None, description="Override the configured model")


class ClassifyResponse(BaseModel):
    intent: str
    # When the model answers with something outside the allowed set we
    # coerce to "unknown" and mark confident=False so callers can decide
    # whether to route to a human.
    confident: bool
    raw_label: str
    allowed_intents: list[str]
    model: str
    tenant: str
    request_id: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging()
    log = get_logger(__name__)
    log.info(
        "startup",
        model=settings.openrouter_model,
        intents=settings.intent_list,
    )
    yield
    log.info("shutdown")


app = FastAPI(
    title="intent-classifier",
    version="0.1.0",
    description="DevOps platform demo: per-tenant utterance-to-intent classifier.",
    lifespan=lifespan,
)


@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
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
        log.exception("unhandled_error")
        requests_total.labels(endpoint=request.url.path, status="500").inc()
        return JSONResponse({"detail": "internal error", "request_id": request_id}, status_code=500)
    response.headers["x-request-id"] = request_id
    requests_total.labels(endpoint=request.url.path, status=str(response.status_code)).inc()
    log.info("request", status=response.status_code)
    return response


@app.get("/health", tags=["infra"])
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready", tags=["infra"])
def ready() -> dict[str, str]:
    if not settings.openrouter_api_key:
        raise HTTPException(status_code=503, detail="openrouter api key not configured")
    return {"status": "ready"}


@app.get("/metrics", tags=["infra"], include_in_schema=False)
def metrics() -> Response:
    return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)


@app.post("/v1/classify", response_model=ClassifyResponse, tags=["classifier"])
async def classify_endpoint(req: ClassifyRequest, request: Request) -> ClassifyResponse:
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    try:
        body = await classify(req.utterance, model=req.model)
    except OpenRouterError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    choices = body.get("choices") or []
    if not choices:
        raise HTTPException(status_code=502, detail="OpenRouter returned no choices")

    raw = (choices[0].get("message", {}).get("content") or "").strip().lower()
    # Strip anything after the first whitespace / punctuation - if the
    # model got chatty despite the prompt, take the first token.
    head = raw.split()[0] if raw else ""
    head = head.strip(".,;:!?\"'`")

    allowed = settings.intent_list
    if head in allowed:
        intent, confident = head, True
    else:
        # Model returned a label we don't recognize. Emit a metric so we
        # can track prompt drift / model misbehaviour over time.
        intent, confident = "unknown", False

    classifications_total.labels(intent=intent, outcome="ok" if confident else "out_of_set").inc()

    return ClassifyResponse(
        intent=intent,
        confident=confident,
        raw_label=raw,
        allowed_intents=allowed,
        model=body.get("model", req.model or settings.openrouter_model),
        tenant=settings.tenant,
        request_id=request_id,
    )
