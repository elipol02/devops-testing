"""structlog setup.

Why JSON logs:
    * Loki/Azure Monitor/Datadog all index JSON-formatted logs FAR better
      than text blobs. Every field is queryable: "give me all ERROR logs
      for tenant=acme where status=502."
    * A human-readable "console" renderer is easy to layer for local dev;
      we skip it here to keep the demo simple. See structlog.dev.ConsoleRenderer.

Why bind service/tenant/environment automatically:
    Every log line gets these three labels. Makes multi-tenant log slicing
    trivial in Loki/ELK. Also means app code doesn't have to remember to
    include them.
"""

import logging
import sys

import structlog

from app.config import settings


def configure_logging() -> None:
    """Configure structlog to emit single-line JSON suitable for log aggregators."""
    # Translate "INFO" -> logging.INFO int. getattr with default handles
    # invalid values gracefully (e.g. someone sets LOG_LEVEL=verbose).
    level = getattr(logging, settings.log_level.upper(), logging.INFO)

    # stdlib logging config: stdout only, no prefixes (structlog writes the
    # full JSON message). K8s captures container stdout; don't log to files.
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=level,
    )

    # Processor chain - each function transforms the log dict in order.
    # Order MATTERS: add_log_level has to run before JSONRenderer can dump
    # it, etc.
    structlog.configure(
        processors=[
            # Pulls context bound via bind_contextvars (request_id, path...)
            # into every log line emitted during the request.
            structlog.contextvars.merge_contextvars,
            # Adds "level": "info"/"error" field.
            structlog.processors.add_log_level,
            # ISO-8601 UTC timestamp. UTC = no timezone confusion in logs.
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            # Adds "stack" frame info to .info/.warning calls when requested.
            structlog.processors.StackInfoRenderer(),
            # Converts exc_info=True on log.exception() into a "exception"
            # field with the formatted traceback.
            structlog.processors.format_exc_info,
            # Final step: serialize to JSON.
            structlog.processors.JSONRenderer(),
        ],
        # make_filtering_bound_logger short-circuits log calls below the
        # threshold BEFORE running processors. Big perf win at scale.
        wrapper_class=structlog.make_filtering_bound_logger(level),
        # Use stdlib loggers underneath so uvicorn/fastapi logs go through
        # the same pipeline.
        logger_factory=structlog.stdlib.LoggerFactory(),
        # Cache the bound logger per name so get_logger is cheap to call
        # per-request.
        cache_logger_on_first_use=True,
    )


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    # .bind returns a NEW logger with the extra fields pre-attached. Called
    # everywhere in the app; those three fields show up in every log line.
    return structlog.get_logger(name).bind(
        service="agent-echo",
        tenant=settings.tenant,
        environment=settings.environment,
    )
