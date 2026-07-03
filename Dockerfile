# syntax=docker/dockerfile:1.7

# ---- builder: resolve deps into an isolated user site-packages dir ----
FROM python:3.12-slim AS builder

WORKDIR /build
COPY app/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ---- runtime: minimal image, non-root user, no build tools ----
FROM python:3.12-slim AS runtime

RUN groupadd --system --gid 1000 appuser \
    && useradd --system --uid 1000 --gid appuser --home-dir /app --shell /sbin/nologin appuser

WORKDIR /app

COPY --from=builder --chown=appuser:appuser /root/.local /app/.local
COPY --chown=appuser:appuser app/main.py app/__init__.py /app/

ENV PATH=/app/.local/bin:$PATH \
    HOME=/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

USER 1000
EXPOSE 8000

# Container-level healthcheck mirrors the Kubernetes liveness probe so the
# image is also useful standalone (docker run) or under plain Docker Compose.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0) if urllib.request.urlopen('http://127.0.0.1:8000/health').status == 200 else sys.exit(1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
