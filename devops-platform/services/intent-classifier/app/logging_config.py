"""structlog setup for intent-classifier.

Same shape as agent-echo/app/logging_config.py - the only meaningful
difference is the service label bound onto every log line. In production
you'd factor this into a shared library (e.g. devops-platform/libs/obs-py)
and import it. For the demo we keep services self-contained so you can read
each one top-to-bottom without chasing imports across the repo.
"""

import logging
import sys

import structlog

from app.config import settings


def configure_logging() -> None:
    level = getattr(logging, settings.log_level.upper(), logging.INFO)
    logging.basicConfig(format="%(message)s", stream=sys.stdout, level=level)

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(level),
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    return structlog.get_logger(name).bind(
        service="intent-classifier",
        tenant=settings.tenant,
        environment=settings.environment,
    )
