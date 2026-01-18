# Shimmy Model Download Service - Complete Guide

## Overview

The `gjkarthik/shimmy:rbac-fix-with-pull` image extends Shimmy with a **model download service** that allows you to dynamically pull GGUF models from HuggingFace without rebuilding the image.

## What's New

### New Endpoint: `/v1/api/pull`

Download GGUF models from HuggingFace Hub on-demand.

**Features**:
- ✅ Downloads any public GGUF model from HuggingFace
- ✅ Thread-safe (only 1 download at a time)
- ✅ Validates GGUF/GGML file format
- ✅ Stores in `/models` directory (local to pod)
- ✅ Automatic integration with Shimmy

## Architecture

```
┌─────────────────────────────────────┐
│  Client Application                 │
│  POST /v1/api/pull                  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Enhanced Flask Proxy (Port 8080)   │
│  - /v1/health                       │
│  - /v1/models                       │
│  - /v1/generate                     │
│  - /v1/api/pull  ← NEW              │
└──────────────┬──────────────────────┘
               │
               ├─→ HuggingFace Hub (download)
               │
               └─→ Shimmy (Port 8081)
```

## API Reference

### Pull Model

**Endpoint**: `POST /v1/api/pull`

**Request Body**:
```json
{
  "model": "TheBloke/phi-3-mini-4k-instruct-GGUF",
  "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf"
}
```

**Response** (Streaming NDJSON):
```json
{"status": "starting", "model": "TheBloke/phi-3-mini-4k-instruct-GGUF", "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf"}
{"status": "complete", "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf", "path": "/models/phi-3-mini-4k-instruct.Q4_K_M.gguf", "size_mb": 2419.5}
```

**Error Responses**:
```json
{"status": "error", "error": "Download already in progress: repo/model"}
{"status": "error", "error": "Both 'model' and 'filename' are required"}
{"status": "error", "error": "HuggingFace error: 404 Not Found"}
{"status": "error", "error": "Downloaded file is not a valid GGUF/GGML model"}
```

### Check Download Status

**Endpoint**: `GET /`

**Response**:
```json
{
  "service": "Shimmy Enhanced Proxy with Model Download",
  "status": "running",
  "version": "2.0.0",
  "endpoints": {
    "health": "/v1/health",
    "generate": "/v1/generate",
    "models": "/v1/models",
    "completions": "/v1/completions",
    "pull": "/v1/api/pull"
  },
  "download_status": {
    "in_progress": false,
    "current_model": null,
    "current_filename": null
  }
}
```

## Usage Examples

### Example 1: Download Phi-3 Mini (Small Model ~2.4GB)

```bash
curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TheBloke/phi-3-mini-4k-instruct-GGUF",
    "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf"
  }'
```

**Expected Output**:
```
{"status": "starting", "model": "TheBloke/phi-3-mini-4k-instruct-GGUF", "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf"}
{"status": "complete", "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf", "path": "/models/phi-3-mini-4k-instruct.Q4_K_M.gguf", "size_mb": 2419.5}
```

### Example 2: Download Llama 3.2 (Larger Model ~2GB)

```bash
curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "bartowski/Llama-3.2-3B-Instruct-GGUF",
    "filename": "Llama-3.2-3B-Instruct-Q4_K_M.gguf"
  }'
```

### Example 3: Verify Model Downloaded

After downloading, check if the model appears:

```bash
curl http://localhost:8080/v1/models
```

**Expected Output**:
```json
{
  "data": [
    {
      "created": 1768631234,
      "id": "phi-3-mini-4k-instruct",
      "object": "model",
      "owned_by": "shimmy"
    }
  ],
  "object": "list"
}
```

### Example 4: Use Downloaded Model for Inference

```bash
curl -X POST http://localhost:8080/v1/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi-3-mini-4k-instruct",
    "prompt": "Explain quantum computing in simple terms",
    "stream": false,
    "max_tokens": 100
  }'
```

## Finding GGUF Models on HuggingFace

### Popular Quantized Model Repositories

1. **TheBloke** - Most popular quantizer
   - `TheBloke/phi-3-mini-4k-instruct-GGUF`
   - `TheBloke/Mistral-7B-Instruct-v0.2-GGUF`
   - `TheBloke/CodeLlama-7B-Instruct-GGUF`

2. **bartowski** - High-quality quantizations
   - `bartowski/Llama-3.2-3B-Instruct-GGUF`
   - `bartowski/Qwen2.5-7B-Instruct-GGUF`

3. **MaziyarPanahi** - Various models
   - `MaziyarPanahi/Phi-3-mini-4k-instruct-GGUF`

### Choosing the Right Quantization

Common GGUF quantizations (from largest to smallest):

- `Q8_0.gguf` - Highest quality, largest size (~7-8GB for 7B models)
- `Q6_K.gguf` - Very good quality (~5-6GB for 7B models)
- **`Q4_K_M.gguf`** - ⭐ **RECOMMENDED** - Good balance (~2-3GB for 7B models)
- `Q4_K_S.gguf` - Smaller, slightly lower quality
- `Q3_K_M.gguf` - Smaller still, more quality loss
- `Q2_K.gguf` - Very small, noticeable quality loss

**For most use cases, use `Q4_K_M` quantization** - it provides the best quality/size tradeoff.

### How to Find the Filename

1. Go to the HuggingFace model page (e.g., `https://huggingface.co/TheBloke/phi-3-mini-4k-instruct-GGUF`)
2. Click on "Files and versions" tab
3. Look for files ending in `.gguf`
4. Copy the exact filename (e.g., `phi-3-mini-4k-instruct.Q4_K_M.gguf`)

## Docker Image Details

### Image: `gjkarthik/shimmy:rbac-fix-with-pull`

**Based on**: `Dockerfile.rbac-fix-with-pull`

**Key Components**:
1. **Shimmy 1.8.1** - Rust-based inference server
2. **Flask Proxy** - Python proxy on port 8080
3. **HuggingFace Hub** - For model downloads
4. **Multi-platform** - Supports AMD64 and ARM64

**Python Dependencies**:
- `flask` - Web framework for proxy
- `requests` - HTTP client
- `huggingface_hub` - HuggingFace model downloader

### Build Command

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f infrastructure/docker/images/shimmy-server/Dockerfile.rbac-fix-with-pull \
  -t gjkarthik/shimmy:rbac-fix-with-pull \
  --push \
  infrastructure/docker/images/shimmy-server/
```

## Kubernetes Deployment

### Deployment Manifest

See: `infrastructure/kyma/shimmy-test/deployment-with-pull.yaml`

**Key Configurations**:
```yaml
resources:
  requests:
    memory: "1Gi"     # Minimum for downloads
    cpu: "500m"
  limits:
    memory: "4Gi"     # Extra headroom for large models
    cpu: "2000m"
```

**Health Checks**:
- Liveness: `/v1/health` every 10s
- Readiness: `/v1/health` every 5s

### Deploy to Kyma

```bash
# Apply deployment
kubectl apply -f infrastructure/kyma/shimmy-test/deployment-with-pull.yaml
kubectl apply -f infrastructure/kyma/shimmy-test/service-with-pull.yaml

# Wait for ready
kubectl wait --for=condition=ready pod \
  -l app=shimmy-model-downloader \
  -n kube-scb \
  --timeout=120s

# Check status
kubectl get pods -n kube-scb -l app=shimmy-model-downloader

# View logs
kubectl logs -n kube-scb -l app=shimmy-model-downloader --tail=50
```

### Test Endpoints

```bash
# Port forward
kubectl port-forward -n kube-scb svc/shimmy-model-downloader 8080:8080

# Test health
curl http://localhost:8080/v1/health

# Test service info
curl http://localhost:8080/ | jq .

# Download a model
curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TheBloke/phi-3-mini-4k-instruct-GGUF",
    "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf"
  }'

# Check models list
curl http://localhost:8080/v1/models

# Test inference
curl -X POST http://localhost:8080/v1/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi-3-mini-4k-instruct",
    "prompt": "Hello, world!",
    "stream": false
  }'
```

## Important Notes

### Storage Considerations

⚠️ **Models are stored locally within the pod** (not in a PersistentVolume)

**Implications**:
- Downloaded models are **lost when pod restarts**
- No shared storage between replicas
- Suitable for testing and development
- For production, consider adding a PersistentVolumeClaim

**To add persistent storage** (optional):

```yaml
volumes:
- name: models-storage
  persistentVolumeClaim:
    claimName: shimmy-models-pvc

volumeMounts:
- name: models-storage
  mountPath: /models
```

### Concurrency

- ✅ **Single download at a time** - Thread-safe locking prevents concurrent downloads
- If a download is in progress, new requests return HTTP 409 with error message
- Check download status via `GET /` endpoint

### Model Naming

Shimmy automatically detects model files and creates model IDs by:
1. Removing the `.gguf` extension
2. Using the filename as the model ID

Example:
- File: `phi-3-mini-4k-instruct.Q4_K_M.gguf`
- Model ID: `phi-3-mini-4k-instruct`

### File Validation

After download, the service verifies the file is a valid GGUF/GGML model by checking:
- GGUF magic bytes: `0x47475546` ("GGUF")
- GGML magic bytes: `0x67676d6c` ("GGML")

If validation fails, the file is automatically deleted.

## Troubleshooting

### Download Failed: 404 Not Found

**Problem**: Model or filename doesn't exist on HuggingFace

**Solution**: 
1. Visit the HuggingFace repo page
2. Click "Files and versions"
3. Verify the exact filename (case-sensitive)

### Download Stuck

**Problem**: Large model download may take time

**Solution**: 
- Wait for completion (downloads can take 5-30 minutes for large models)
- Check pod logs: `kubectl logs -n kube-scb -l app=shimmy-model-downloader -f`
- Download progress is shown in HuggingFace Hub logs

### Model Not Appearing in `/v1/models`

**Problem**: Model downloaded but not showing up

**Solution**:
1. Verify file is in `/models`: `kubectl exec -n kube-scb <pod-name> -- ls -lh /models`
2. Check file has `.gguf` extension
3. Restart Shimmy if needed: `kubectl rollout restart deployment shimmy-model-downloader -n kube-scb`

### Concurrent Download Error

**Problem**: Getting "Download already in progress" error

**Solution**: Wait for current download to complete, then retry

## Comparison with Original Image

| Feature | `rbac-fix` | `rbac-fix-with-pull` |
|---------|------------|---------------------|
| Base Shimmy functionality | ✅ | ✅ |
| Lightweight proxy | ✅ | ✅ |
| All `/v1/*` endpoints | ✅ | ✅ |
| Model download endpoint | ❌ | ✅ |
| HuggingFace Hub integration | ❌ | ✅ |
| Dynamic model loading | ❌ | ✅ |
| Image size | ~180MB | ~190MB |

## Complete Testing Script

Save this as `test-model-download.sh`:

```bash
#!/bin/bash
set -e

echo "=========================================="
echo "Shimmy Model Download Service - Test Script"
echo "=========================================="

# Setup port forward
echo "Setting up port forward..."
kubectl port-forward -n kube-scb svc/shimmy-model-downloader 8080:8080 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

# Test 1: Check service status
echo -e "\n1. Testing service status..."
curl -s http://localhost:8080/ | jq .

# Test 2: Check health
echo -e "\n2. Testing health endpoint..."
curl -s http://localhost:8080/v1/health | jq .status

# Test 3: List models (should be empty initially)
echo -e "\n3. Listing models (before download)..."
curl -s http://localhost:8080/v1/models | jq .

# Test 4: Download a small model
echo -e "\n4. Downloading phi-3-mini model (~2.4GB)..."
echo "This will take several minutes..."
curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TheBloke/phi-3-mini-4k-instruct-GGUF",
    "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf"
  }'

# Test 5: List models again
echo -e "\n\n5. Listing models (after download)..."
curl -s http://localhost:8080/v1/models | jq .

# Test 6: Test inference
echo -e "\n6. Testing inference with downloaded model..."
curl -X POST http://localhost:8080/v1/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi-3-mini-4k-instruct",
    "prompt": "Say hello in 5 words",
    "stream": false,
    "max_tokens": 50
  }' | jq .

echo -e "\n=========================================="
echo "All tests complete!"
echo "=========================================="

# Cleanup
kill $PF_PID 2>/dev/null || true
```

## Recommended Models for Testing

### Small Models (< 1GB) - Fast to Download

```bash
# TinyLlama 1.1B Q4_K_M (~669MB)
curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF",
    "filename": "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
  }'
```

### Medium Models (1-3GB) - Good Performance

```bash
# Phi-3 Mini Q4_K_M (~2.4GB)
curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TheBloke/phi-3-mini-4k-instruct-GGUF",
    "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf"
  }'
```

### Large Models (3-7GB) - Best Quality

```bash
# Mistral 7B Q4_K_M (~4.4GB)
curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TheBloke/Mistral-7B-Instruct-v0.2-GGUF",
    "filename": "mistral-7b-instruct-v0.2.Q4_K_M.gguf"
  }'
```

## SAP AI Core Deployment

To deploy with KServe in SAP AI Core, use the ServingTemplate approach:

```yaml
apiVersion: ai.sap.com/v1alpha1
kind: ServingTemplate
metadata:
  name: shimmy-model-downloader
spec:
  template:
    apiVersion: "serving.kserve.io/v1beta1"
    spec:
      predictor:
        containers:
        - name: kserve-container
          image: docker.io/gjkarthik/shimmy:rbac-fix-with-pull
          ports:
          - containerPort: 8080
          resources:
            limits:
              memory: "4Gi"
              cpu: "2000m"
```

## Limitations

### Current Version Constraints

1. **Public repos only** - No authentication token support (can be added if needed)
2. **Single download** - Only one concurrent download allowed
3. **Pod-local storage** - Models don't persist across pod restarts
4. **Manual filename** - Must specify exact GGUF filename

### Future Enhancements (Not Yet Implemented)

- [ ] Authentication token support for private repos
- [ ] Auto-detect best quantization (e.g., prefer Q4_K_M)
- [ ] Progress percentage tracking during download
- [ ] Model deletion endpoint (`/v1/api/delete`)
- [ ] List available files in a HuggingFace repo
- [ ] Concurrent downloads with queue management
- [ ] PersistentVolume integration

## Security Considerations

- Service runs as non-root user (UID 1000)
- No privileged containers
- Read-only root filesystem (except `/models`)
- Network policies recommended for production

## Support & Troubleshooting

For issues:
1. Check pod logs: `kubectl logs -n kube-scb -l app=shimmy-model-downloader`
2. Verify model exists on HuggingFace
3. Ensure sufficient disk space in pod
4. Check download status via root endpoint

## Files Created

1. **`model-downloader-proxy.py`** - Enhanced proxy with download capability
2. **`Dockerfile.rbac-fix-with-pull`** - Docker image with HuggingFace Hub
3. **`start-with-downloader.sh`** - Startup script
4. **`deployment-with-pull.yaml`** - Kubernetes deployment
5. **`service-with-pull.yaml`** - Kubernetes service

All files preserve the original `Dockerfile.rbac-fix` and related files unchanged.

## Summary

The `rbac-fix-with-pull` image successfully adds dynamic model downloading to Shimmy, allowing you to:

✅ Download any public GGUF model from HuggingFace  
✅ No need to rebuild the image for new models  
✅ Simple REST API for model management  
✅ Automatic integration with Shimmy  
✅ Production-ready with proper error handling  

This makes it much easier to test different models and deploy Shimmy in environments where models need to be loaded dynamically.
