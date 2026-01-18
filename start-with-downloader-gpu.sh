#!/bin/bash
set -e

echo "=========================================="
echo "Starting Shimmy with GPU Support (CUDA)"
echo "=========================================="
echo "Shimmy Port: ${SHIMMY_PORT:-8081}"
echo "Models Path: ${SHIMMY_MODEL_PATH:-/models}"
echo "GPU Backend: ${SHIMMY_GPU_BACKEND:-cuda}"
echo "Proxy Port: 8080"
echo "=========================================="

# Verify models directory is writable (already created in Dockerfile)
echo "Checking models directory..."
if [ -w "${SHIMMY_MODEL_PATH:-/models}" ]; then
    echo "✅ Models directory is writable"
else
    echo "⚠️ WARNING: Models directory may not be writable"
fi
echo "=========================================="

# Check if GPU is available (nvidia-smi comes from K8s device plugin)
echo "Checking GPU availability..."
if command -v nvidia-smi &> /dev/null; then
    echo "✅ GPU detected:"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || echo "⚠️ nvidia-smi available but query failed"
else
    echo "⚠️ nvidia-smi not found - GPU may not be available"
    echo "   Shimmy will attempt to use GPU backend anyway (may fallback to CPU)"
fi
echo "=========================================="

# Start Shimmy on internal port 8081 with GPU backend
echo "Starting Shimmy with GPU backend on port 8081..."
shimmy serve \
    --bind 0.0.0.0:8081 \
    --gpu-backend ${SHIMMY_GPU_BACKEND:-cuda} \
    --model-path ${SHIMMY_MODEL_PATH:-/models} &
SHIMMY_PID=$!

# Wait for Shimmy to be ready
echo "Waiting for Shimmy to be ready..."
for i in {1..30}; do
    if curl -sf http://localhost:8081/health > /dev/null 2>&1; then
        echo "✅ Shimmy is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ ERROR: Shimmy failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

# Start the enhanced proxy on port 8080 (external port)
echo "Starting enhanced proxy with model download on port 8080..."
python3 /app/model-downloader-proxy.py &
PROXY_PID=$!

# Wait for proxy to be ready
echo "Waiting for proxy to be ready..."
for i in {1..10}; do
    if curl -sf http://localhost:8080/ > /dev/null 2>&1; then
        echo "✅ Proxy is ready!"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "❌ ERROR: Proxy failed to start within 10 seconds"
        kill $SHIMMY_PID
        exit 1
    fi
    sleep 1
done

echo "=========================================="
echo "🚀 GPU-Accelerated Shimmy Started!"
echo "=========================================="
echo "Shimmy:        http://localhost:8081 (internal)"
echo "Proxy:         http://localhost:8080 (external)"
echo "GPU Backend:   ${SHIMMY_GPU_BACKEND:-cuda}"
echo "=========================================="
echo "Available Endpoints:"
echo "  /v1/health     - Health check"
echo "  /v1/models     - List models"
echo "  /v1/generate   - Generate text (GPU-accelerated)"
echo "  /v1/api/pull   - Download models from HuggingFace"
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
        echo "⚠️ Shimmy process terminated - restarting with new models..."
        
        # Restart Shimmy on internal port 8081 with GPU
        shimmy serve \
            --bind 0.0.0.0:8081 \
            --gpu-backend ${SHIMMY_GPU_BACKEND:-cuda} \
            --model-path ${SHIMMY_MODEL_PATH:-/models} &
        SHIMMY_PID=$!
        
        # Wait for Shimmy to be ready
        echo "Waiting for restarted Shimmy to be ready..."
        for i in {1..30}; do
            if curl -sf http://localhost:8081/health > /dev/null 2>&1; then
                echo "✅ Shimmy restarted successfully with new models!"
                break
            fi
            if [ $i -eq 30 ]; then
                echo "❌ ERROR: Shimmy failed to restart within 30 seconds"
                cleanup
                exit 1
            fi
            sleep 1
        done
    fi
    if ! kill -0 $PROXY_PID 2>/dev/null; then
        echo "❌ ERROR: Proxy process died unexpectedly"
        cleanup
        exit 1
    fi
    sleep 2
done
