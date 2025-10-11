FROM python:3.11-slim

WORKDIR /app

# Install runtime deps needed for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App
COPY app.py .

# Non-root
RUN useradd -m -u 1000 streamlit && chown -R streamlit:streamlit /app
USER streamlit

EXPOSE 8501

HEALTHCHECK CMD curl --fail http://localhost:8501/_stcore/health || exit 1

CMD ["streamlit", "run", "app.py", \
     "--server.port=8501", \
     "--server.address=0.0.0.0", \
     "--server.headless=true", \
     "--server.enableXsrfProtection=true", \
     "--server.enableCORS=false"]
