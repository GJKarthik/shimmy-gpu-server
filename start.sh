#!/bin/bash
# Startup script for Shimmy (Rust) with proxy wrapper

set -e

echo "[Shimmy] Starting Shimmy inference server on port 8080..."
echo "[Shimmy] Model directory: $SHIMMY_BASE_GGUF"
echo "[Shimmy] GPU support: CUDA 12.1.0"

# Start Shimmy with environment variables
shimmy serve &
SHIMMY_PID=$!

# Wait for Shimmy to be ready with retries
echo "[Shimmy] Waiting for Shimmy to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
until curl -f http://localhost:8080/health > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "[Shimmy] ERROR: Shimmy failed to start within timeout"
        exit 1
    fi
    echo "[Shimmy] Waiting for health endpoint... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

echo "[Shimmy] Shimmy is ready and responding to health checks"

echo "[Proxy] Starting OpenAI-compatible proxy on port 8000..."
python3 /opt/shimmy/proxy-wrapper.py &
PROXY_PID=$!

# Wait for proxy to be ready
echo "[Proxy] Waiting for proxy to be ready..."
sleep 3
until curl -f http://localhost:8000/health > /dev/null 2>&1; do
    echo "[Proxy] Waiting for proxy health endpoint..."
    sleep 1
done

echo "[System] Both services started successfully"
echo "[System] - Shimmy: http://localhost:8080"
echo "[System] - Proxy: http://localhost:8000"
echo "[System] Health endpoints available at both ports"

# Function to handle shutdown
shutdown() {
    echo "[System] Shutting down services..."
    kill $SHIMMY_PID $PROXY_PID 2>/dev/null
    wait $SHIMMY_PID $PROXY_PID 2>/dev/null
    echo "[System] Shutdown complete"
    exit 0
}

# Trap signals
trap shutdown SIGTERM SIGINT

# Wait for both processes
wait $SHIMMY_PID $PROXY_PID
