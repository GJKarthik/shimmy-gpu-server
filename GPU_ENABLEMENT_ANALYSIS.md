# Shimmy GPU Enablement Analysis for SAP AI Core T4

## Current Status: CPU-Only ❌

Your current deployment is running **CPU-only** inference despite having an NVIDIA T4 GPU available.

## Root Cause Analysis

### 1. Dockerfile Issue
**Current**: `RUN cargo install shimmy`
- This installs with **default features** = `["huggingface", "llama"]`
- Does NOT include `llama-cuda` feature
- Result: CPU-only binary

**Fix Needed**: `RUN cargo install shimmy --features llama-cuda,huggingface`

### 2. Startup Script Issue  
**Current**: `shimmy serve --bind 0.0.0.0:8081 --model-path /models`
- No `--gpu-backend` flag specified
- Defaults to CPU

**Fix Needed**: `shimmy serve --bind 0.0.0.0:8081 --gpu-backend cuda --model-path /models`

### 3. Kubernetes Deployment
**Current**: No GPU resource requests
**Fix Needed**: Add `nvidia.com/gpu: 1` resource request

## From Shimmy Source Code

### Cargo.toml Features:
```toml
default = ["huggingface", "llama"]  # CPU-only
llama-cuda = ["llama", "shimmy-llama-cpp-2/cuda"]  # Adds CUDA support
gpu = ["huggingface", "llama-cuda", "llama-vulkan", "llama-opencl"]  # All GPU backends
```

### Official Dockerfile (from shimmy/Dockerfile):
```dockerfile
FROM rust:1.85-slim as builder
# ... build deps ...
RUN cargo build --release --features huggingface  # CPU-only!

FROM debian:bookworm-slim  # Plain Debian, no NVIDIA base!
# ... runtime deps ...
```

### Official CUDA Build (from .github/workflows/release.yml):
```bash
cargo build --release --no-default-features --features llama-cuda
# Still uses plain Debian runtime!
```

## Key Insight: No NVIDIA Runtime Base Needed! ✅

Shimmy's llama.cpp bindings are **statically linked** with CUDA support at compile time. The CUDA runtime libraries are loaded dynamically from the **host** (Kubernetes node) via device plugins.

This is why:
1. Official Dockerfile uses plain `debian:bookworm-slim`
2. No NVIDIA base image needed
3. Just need the feature flag during build
4. CUDA libraries come from the K8s node, not the container

## Corrected Solution (Minimal Changes)

### Change 1: Dockerfile
```dockerfile
# BEFORE
RUN cargo install shimmy

# AFTER  
RUN cargo install shimmy --features llama-cuda,huggingface
```

### Change 2: Startup Script
```bash
# BEFORE
shimmy serve --bind 0.0.0.0:8081 --model-path /models &

# AFTER
shimmy serve --bind 0.0.0.0:8081 --gpu-backend cuda --model-path /models &
```

### Change 3: Kubernetes Deployment
```yaml
resources:
  limits:
    nvidia.com/gpu: 1
  requests:
    nvidia.com/gpu: 1
```

## Why This Works

1. **Build Time**: `llama-cuda` feature compiles CUDA support into the binary
2. **Runtime**: Kubernetes mounts CUDA libraries from node into container
3. **Detection**: Shimmy detects GPU via nvidia-smi (provided by K8s device plugin)
4. **Inference**: Uses CUDA for 10x faster performance

## Expected Performance

| Metric | CPU (Current) | GPU (T4) | Improvement |
|--------|---------------|----------|-------------|
| Model Loading | ~15s | ~2s | **7.5x faster** |
| Inference (per token) | ~200ms | ~20ms | **10x faster** |
| Total Response (30 tokens) | ~6s | ~0.6s | **10x faster** |

## Implementation Plan

1. Create `Dockerfile.gpu` with `llama-cuda` feature
2. Create `start-with-downloader-gpu.sh` with `--gpu-backend cuda`
3. Update deployment YAML with GPU resources
4. Build as `v2.7-gpu` tag
5. Deploy and verify with `nvidia-smi` in pod

## Verification Steps

```bash
# 1. Check GPU is visible in pod
kubectl exec -n kube-scb <pod> -- nvidia-smi

# 2. Check Shimmy detected GPU
kubectl logs -n kube-scb <pod> -c shimmy | grep -i "cuda\|gpu"

# 3. Run benchmark
curl -X POST http://localhost:8080/v1/generate \
  -d '{"model": "phi3-lora", "prompt": "Hello", "max_tokens": 30}' \
  -w "\nTime: %{time_total}s\n"
```

Expected: Should see **<1 second** response time vs **~5 seconds** on CPU.
