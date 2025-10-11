FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY router.py .
COPY utils/ ./utils/

# Create non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8500

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8500/health', timeout=5)"

# Run with gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8500", "--workers", "4", "--timeout", "120", "--access-logfile", "-", "--error-logfile", "-", "router:app"]
