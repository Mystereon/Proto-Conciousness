FROM python:3.11-slim AS base

# Build dependencies for llama-cpp-python (compiles C++ code)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies first (cache layer)
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ .

# Models directory (mount as volume)
RUN mkdir -p /models

ENV INDIGO_BASE_DIR=/app \
    INDIGO_HOST=0.0.0.0 \
    INDIGO_PORT=5000 \
    INDIGO_MODEL_DIR=/models \
    INDIGO_CTX_SIZE=2048 \
    INDIGO_MAX_TOKENS=256

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

CMD ["python", "app.py"]
