# Multi-stage build for notebooklm2api
FROM python:3.11-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy project files
COPY pyproject.toml ./
COPY src ./src
COPY README.md ./
COPY LICENSE ./
# Copy potential files needed for readme processing
COPY CHANGELOG.md ./
COPY docs ./docs


# Install build tools
RUN pip install --no-cache-dir build wheel

# Build wheel
# This avoids uv complexity and lock file issues
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /app/wheels .

# Runtime stage
FROM python:3.11-slim

# Install runtime dependencies for Playwright
RUN apt-get update && apt-get install -y \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy wheels from builder
COPY --from=builder /app/wheels /wheels

# Install dependencies from wheels and PyPI
# Install notebooklm-py with browser support (includes playwright)
RUN pip install --no-cache-dir --find-links=/wheels 'notebooklm-py[browser]' && \
    pip install --no-cache-dir fastapi uvicorn

# Copy API server code
COPY api_server.py ./

# Install Playwright browsers (chromium only for auth)
RUN playwright install chromium

# Create directory for auth storage
RUN mkdir -p /root/.notebooklm && chmod 700 /root/.notebooklm

# Expose API port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/health', timeout=5.0)" || exit 1

# Run the API server
CMD ["python", "api_server.py"]
