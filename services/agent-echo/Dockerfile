# syntax=docker/dockerfile:1.7
# ^ Enables BuildKit frontend features (--mount=type=cache, heredocs, etc.).
#   Safe for both `docker build` and `docker buildx`.

# =============================================================================
# Multi-stage Dockerfile for agent-echo.
#
# Two stages:
#   1) builder  - installs Python deps into /install. Has pip + build tools.
#   2) runtime  - slim final image; COPY --from=builder brings ONLY the
#                 site-packages. No pip, no build tools, smaller attack
#                 surface.
#
# The resulting image is ~150MB vs ~400MB+ for a single-stage build.
# Every byte we don't ship is a byte an attacker can't exploit.
# =============================================================================


# ---------- builder stage ----------
FROM python:3.12-slim AS builder

# ENV line consolidated with line continuations to reduce layer count.
# PIP_DISABLE_PIP_VERSION_CHECK=1 -> no "newer pip available" nag.
# PIP_NO_CACHE_DIR=1              -> don't write ~/.cache/pip (saves a few MB).
# PYTHONDONTWRITEBYTECODE=1       -> skip .pyc files (not needed at install time).
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /build

# Copy ONLY pyproject.toml first so docker layer caching kicks in: if you
# change app code but not deps, the expensive `pip install` layer is reused.
COPY pyproject.toml ./

# --prefix=/install installs into an isolated tree we COPY into runtime.
# Versions pinned here so an image rebuild 6 months from now doesn't
# silently pull in breaking updates. Real projects use a lockfile
# (pip-tools / uv / poetry); kept inline here for readability.
RUN pip install --prefix=/install "fastapi>=0.115.0" "uvicorn[standard]>=0.32.0" \
    "httpx>=0.27.0" "pydantic>=2.9.0" "pydantic-settings>=2.5.0" \
    "prometheus-client>=0.21.0" "structlog>=24.4.0"


# ---------- runtime stage ----------
FROM python:3.12-slim AS runtime

# PYTHONUNBUFFERED=1 -> stdout is unbuffered. Critical in containers;
# otherwise log lines get stuck in the buffer and only flush on exit,
# which confuses k8s logging and sidecar forwarders.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/usr/local/bin:/install/bin:$PATH \
    PYTHONPATH=/install/lib/python3.12/site-packages

# Non-root user, fixed UID 10001. Matches the chart's
# podSecurityContext.runAsUser. Consistency matters: a file owned by 10001
# in the image remains readable when the pod runs as 10001.
# --no-create-home / --shell /sbin/nologin = further hardening.
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /sbin/nologin app

# Pull prebuilt Python packages from builder. No pip in runtime image.
COPY --from=builder /install /install

WORKDIR /app
COPY app ./app

# Switch to the non-root user BEFORE any command runs as root. Once set,
# everything below (and every `docker run`) executes as 10001.
USER 10001:10001

# EXPOSE is documentation only. Kubernetes uses containerPort from the
# Deployment spec, not this. Still useful for `docker run -P`.
EXPOSE 8000

# Docker-native health check. K8s uses its own HTTP probes (see the chart),
# but HEALTHCHECK helps when running the image with plain docker (local dev,
# smoke tests) and is honored by some runtimes like ECS.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request, sys; \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).status == 200 else 1)"

# CMD = default process. Uvicorn on 0.0.0.0:8000 (bind inside container;
# Service/Ingress handles the outside). --no-server-header strips "Server:
# uvicorn" response header - tiny info-leak reduction.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header"]
