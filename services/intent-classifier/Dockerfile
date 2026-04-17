# syntax=docker/dockerfile:1.7

# =============================================================================
# intent-classifier: second example custom integration.
#
# Structurally IDENTICAL to services/agent-echo/Dockerfile. Real FDEs would
# copy this whole pattern. The whole point of the platform is that every
# service looks the same from the outside, even though the code inside is
# different per customer.
# =============================================================================

FROM python:3.12-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /build
COPY pyproject.toml ./
RUN pip install --prefix=/install "fastapi>=0.115.0" "uvicorn[standard]>=0.32.0" \
    "httpx>=0.27.0" "pydantic>=2.9.0" "pydantic-settings>=2.5.0" \
    "prometheus-client>=0.21.0" "structlog>=24.4.0"


FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/usr/local/bin:/install/bin:$PATH \
    PYTHONPATH=/install/lib/python3.12/site-packages

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /sbin/nologin app

COPY --from=builder /install /install

WORKDIR /app
COPY app ./app

USER 10001:10001

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request, sys; \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).status == 200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header"]
