# Lightweight Shimmy Docker for SAP AI Core
# No baked models - models loaded at runtime from volume or downloaded on-demand
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    SHIMMY_PORT=8080 \
    SHIMMY_HOST=0.0.0.0 \
    SHIMMY_BASE_GGUF=/models

# Install runtime dependencies including Python for proxy
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies for proxy
RUN pip3 install --no-cache-dir flask requests

# Create directory for nobody user (SAP AI Core requirement)
# This is needed because Shimmy may write cache/config to home directory
RUN mkdir -p /nonexistent/.shimmy /models /opt/shimmy && \
    chown -R nobody:nogroup /nonexistent /models /opt/shimmy && \
    chmod -R 770 /nonexistent /models /opt/shimmy

# Download Shimmy binary
RUN curl -L https://github.com/Michael-A-Kuykendall/shimmy/releases/latest/download/shimmy-linux-amd64 \
    -o /opt/shimmy/shimmy && \
    chmod +x /opt/shimmy/shimmy && \
    chown nobody:nogroup /opt/shimmy/shimmy

# Copy proxy wrapper and startup script
COPY --chown=nobody:nogroup proxy-wrapper.py /opt/shimmy/
COPY --chown=nobody:nogroup start.sh /opt/shimmy/
RUN chmod +x /opt/shimmy/start.sh

# Set working directory
WORKDIR /opt/shimmy

# Switch to nobody user for security (SAP AI Core requirement)
USER nobody

# Expose ports
# 8080 for Shimmy server (internal)
# 8000 for OpenAI-compatible proxy (external)
EXPOSE 8080 8000

# Health check (using port 8000 which is externally accessible)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run startup script (starts both Shimmy and proxy)
CMD ["/opt/shimmy/start.sh"]
