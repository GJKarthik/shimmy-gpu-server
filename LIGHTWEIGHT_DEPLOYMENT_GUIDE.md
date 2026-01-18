# Lightweight Shimmy Deployment Guide for SAP AI Core

**Status:** ✅ Optimized for Fast Deployment  
**Date:** January 16, 2026  
**Image Size:** ~500MB (vs 3.5GB with baked models)  
**Build Time:** ~30 seconds (vs 5+ minutes)

---

## Overview

This guide covers deploying the lightweight Shimmy inference server to SAP AI Core with:
- ✅ **No baked models** - Fast build and push
- ✅ **`nobody` user** - SAP AI Core security compliance
- ✅ **GPU support** - CUDA 12.1.0 runtime included
- ✅ **Runtime model loading** - Models loaded from volume or downloaded on-demand
- ✅ **Health checks** - Proper probes on port 8000

---

## Key Improvements

### 1. Nobody User Support (Ollama-style)
```dockerfile
# Create directory for nobody user (SAP AI Core requirement)
RUN mkdir -p /nonexistent/.shimmy /models /opt/shimmy && \
    chown -R nobody:nogroup /nonexistent /models /opt/shimmy && \
    chmod -R 770 /nonexistent /models /opt/shimmy

USER nobody
```

**Why?** SAP AI Core may require non-root containers for security. This ensures:
- Shimmy can write cache/config to home directory
- Model directory is writable
- Compliant with Kubernetes security policies

### 2. No Baked Models
- **Before:** 3.5GB image with Gemma-2B baked in
- **After:** ~500MB image, models at runtime
- **Benefit:** 7x smaller, 10x faster to push

### 3. Volume Mount for Models
```yaml
volumeMounts:
- name: models
  mountPath: /models

volumes:
- name: models
  emptyDir: {}  # For testing, or use PVC for persistence
```

---

## Build and Push

### Step 1: Navigate to Shimmy Directory
```bash
cd infrastructure/docker/images/shimmy-server
```

### Step 2: Build Lightweight Image
```bash
docker build -t docker.io/gjkarthik/shimmy:lightweight .
```

**Expected output:**
```
[+] Building 45.2s (15/15) FINISHED
=> => naming to docker.io/gjkarthik/shimmy:lightweight
```

**Image size:** ~500MB

### Step 3: Push to Docker Hub
```bash
docker push docker.io/gjkarthik/shimmy:lightweight
```

**Push time:** ~30-60 seconds (vs 5+ minutes for full image)

### Step 4: Optional - Tag as Latest
```bash
docker tag docker.io/gjkarthik/shimmy:lightweight docker.io/gjkarthik/shimmy:latest
docker push docker.io/gjkarthik/shimmy:latest
```

---

## Deploy to SAP AI Core

### Option A: Using SAP AI Core UI

1. **Upload ServingTemplate**
   - Go to SAP AI Core → ML Operations → Serving Templates
   - Upload `shimmy-serving-template.yaml`
   - Template name: `shimmy-lightweight`

2. **Create Deployment**
   - Click "Create Deployment"
   - Select `shimmy-lightweight` template
   - Resource plan: `infer.m` (with GPU)
   - Wait for status: **Running**

3. **Check Logs**
   ```
   [Shimmy] Starting Shimmy inference server on port 8080...
   [Shimmy] Model directory: /models
   [Shimmy] GPU support: CUDA 12.1.0
   [Shimmy] Waiting for Shimmy to be ready...
   [Proxy] Starting OpenAI-compatible proxy on port 8000...
   [System] Both services started successfully
   ```

### Option B: Using kubectl

```bash
# Apply the ServingTemplate
kubectl apply -f shimmy-serving-template.yaml

# Check deployment status
kubectl get pods -n <your-namespace>

# View logs
kubectl logs -f <pod-name> -n <your-namespace>
```

---

## Model Loading Options

### Option 1: EmptyDir (Default - For Testing)
```yaml
volumes:
- name: models
  emptyDir: {}
```
- **Pros:** Quick setup, no PVC needed
- **Cons:** Models lost on pod restart
- **Use case:** Testing, ephemeral workloads

### Option 2: Persistent Volume Claim (Production)
```yaml
volumes:
- name: models
  persistentVolumeClaim:
    claimName: shimmy-models-pvc
```

**Create PVC:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shimmy-models-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard
```

**Pre-populate models:**
```bash
# Copy models to PVC
kubectl cp phi3-mini.gguf <pod-name>:/models/phi3-mini.gguf
```

### Option 3: Download at Runtime
Shimmy can download models from HuggingFace on first request:
```bash
# The proxy will forward requests, Shimmy will auto-download
curl -X POST http://deployment-url/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3-mini",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

---

## Health Check Configuration

### Startup Probe
```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 18  # Up to 180s for startup
```
- Gives container time to start Shimmy and proxy
- Checks port 8000 (externally accessible)

### Liveness Probe
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 60
  periodSeconds: 30
```
- Ensures container is alive
- Restarts if unhealthy

### Readiness Probe
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 60
  periodSeconds: 10
```
- Checks if ready to serve traffic
- Removes from load balancer if not ready

---

## API Endpoints

Once deployed, the following endpoints are available:

### 1. Health Check
```bash
curl http://<deployment-url>/health
```

**Response:**
```json
{
  "status": "healthy",
  "proxy": "running",
  "shimmy": "ready",
  "timestamp": 1737008765
}
```

### 2. List Models
```bash
curl http://<deployment-url>/v1/models
```

### 3. Chat Completions (OpenAI-compatible)
```bash
curl -X POST http://<deployment-url>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3-mini",
    "messages": [
      {"role": "user", "content": "What is AI?"}
    ]
  }'
```

### 4. Direct Shimmy API (Internal)
```bash
curl -X POST http://<deployment-url>/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3-mini",
    "prompt": "Explain cloud computing",
    "stream": false
  }'
```

---

## Resource Requirements

### Minimum (CPU-only fallback)
- **CPU:** 2 cores
- **Memory:** 2GB RAM
- **Storage:** 10GB (image + models)
- **GPU:** Optional

### Recommended (GPU)
- **CPU:** 2 cores
- **Memory:** 4GB RAM
- **GPU:** 1x NVIDIA (any CUDA 12.1+ compatible)
- **Storage:** 10GB

### Configuration
```yaml
resources:
  requests:
    memory: "4Gi"
    cpu: "2000m"
    nvidia.com/gpu: "1"
  limits:
    memory: "8Gi"
    cpu: "4000m"
    nvidia.com/gpu: "1"
```

---

## Troubleshooting

### 1. Image Pull Errors
```bash
# Verify image exists
docker pull docker.io/gjkarthik/shimmy:lightweight

# Check imagePullSecret
kubectl get secret ollamadocker -n <namespace>
```

### 2. Health Check Failures
```bash
# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Look for:
[Shimmy] Shimmy is ready and responding to health checks
[System] Both services started successfully
```

**Common issues:**
- Shimmy not starting (check port 8080 binding)
- Proxy not starting (check Python dependencies)
- Port 8000 not accessible (check nobody user permissions)

### 3. Nobody User Permission Issues
```bash
# Check file permissions in container
kubectl exec -it <pod-name> -- ls -la /models
kubectl exec -it <pod-name> -- ls -la /opt/shimmy

# Should show:
drwxrwx--- nobody nogroup /models
drwxrwx--- nobody nogroup /opt/shimmy
```

### 4. Model Loading Issues
```bash
# Check if models directory is writable
kubectl exec -it <pod-name> -- touch /models/test.txt

# Should succeed without permission errors
```

---

## Performance Testing

### Quick Test
```bash
# Test health endpoint
time curl http://<deployment-url>/health

# Should respond in < 100ms
```

### Inference Test
```bash
# Small prompt test
time curl -X POST http://<deployment-url>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3-mini",
    "messages": [{"role": "user", "content": "Say hello"}],
    "max_tokens": 10
  }'
```

**Expected:**
- First request: 10-30s (model download/load)
- Subsequent: 1-5s (model cached)

---

## Next Steps

### 1. Add Model Baking (Optional)
Once the lightweight version works, you can create a variant with baked models:
```dockerfile
# Add after USER nobody line
RUN curl -fsSL -o /models/phi3-mini.gguf \
    https://huggingface.co/...model.gguf
```

### 2. Enable Auto-scaling
```yaml
autoscaling.knative.dev/target: 1
minReplicas: 1
maxReplicas: 5
```

### 3. Add Monitoring
- Prometheus metrics endpoint
- Grafana dashboards
- Alert rules for health failures

---

## Summary

✅ **Lightweight image** (~500MB vs 3.5GB)  
✅ **Fast deployment** (~30s build/push)  
✅ **Security compliant** (nobody user)  
✅ **GPU support** (CUDA 12.1.0)  
✅ **Flexible models** (runtime loading)  
✅ **Production ready** (proper health checks)

The deployment is now optimized for rapid iteration and testing on SAP AI Core!
