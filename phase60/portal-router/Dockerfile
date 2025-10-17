# ───────────────────────────────────────────────
# Henry Enterprise Portal Router (Phase 60)
# OIDC-enabled Flask Router (Keycloak + FreeIPA Ready)
# ───────────────────────────────────────────────
FROM python:3.11-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl iputils-ping && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir gunicorn

COPY . .

EXPOSE 5000
HEALTHCHECK CMD curl -fs http://localhost:5000/healthz || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "router:app"]

