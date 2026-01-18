#!/bin/bash
set -e

echo "=========================================="
echo "Starting Shimmy with Lightweight Proxy"
echo "=========================================="

# Start Shimmy on internal port 8081
echo "Starting Shimmy on port 8081..."
shimmy serve --bind 0.0.0.0:8081 &
SHIMMY_PID=$!

# Wait for Shimmy to be ready
echo "Waiting for Shimmy to be ready..."
for i in {1..30}; do
    if curl -sf http://localhost:8081/health > /dev/null 2>&1; then
        echo "Shimmy is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Shimmy failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

# Start the lightweight proxy on port 8080 (external port)
echo "Starting lightweight proxy on port 8080..."
python3 /app/lightweight-proxy.py &
PROXY_PID=$!

# Wait for proxy to be ready
echo "Waiting for proxy to be ready..."
for i in {1..10}; do
    if curl -sf http://localhost:8080/ > /dev/null 2>&1; then
        echo "Proxy is ready!"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "ERROR: Proxy failed to start within 10 seconds"
        kill $SHIMMY_PID
        exit 1
    fi
    sleep 1
done

echo "=========================================="
echo "Startup Complete!"
echo "Shimmy:        http://localhost:8081 (internal)"
echo "Proxy:         http://localhost:8080 (external)"
echo "=========================================="
echo "Endpoint Mappings:"
echo "  /v1/health   -> Shimmy /health"
echo "  /v1/generate -> Shimmy /api/generate"
echo "  /v1/models   -> Shimmy /v1/models"
echo "=========================================="

# Function to handle shutdown
cleanup() {
    echo "Shutting down..."
    kill $PROXY_PID 2>/dev/null || true
    kill $SHIMMY_PID 2>/dev/null || true
    wait $PROXY_PID 2>/dev/null || true
    wait $SHIMMY_PID 2>/dev/null || true
    echo "Shutdown complete"
}

trap cleanup SIGTERM SIGINT EXIT

# Keep the script running and monitor both processes
while true; do
    if ! kill -0 $SHIMMY_PID 2>/dev/null; then
        echo "ERROR: Shimmy process died"
        cleanup
        exit 1
    fi
    if ! kill -0 $PROXY_PID 2>/dev/null; then
        echo "ERROR: Proxy process died"
        cleanup
        exit 1
    fi
    sleep 5
done
