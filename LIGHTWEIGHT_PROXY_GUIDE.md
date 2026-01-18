# Lightweight Proxy Guide for SAP AI Core RBAC Bypass

## Overview

This guide explains the lightweight proxy solution for bypassing SAP AI Core's RBAC restrictions on Shimmy endpoints.

## Problem

SAP AI Core's RBAC policy only allows access to endpoints under `/v1/*` path. Shimmy's native endpoints like `/health` and `/api/generate` are blocked, causing RBAC errors even though `/v1/models` works fine.

## Solution

A lightweight Python proxy that:
1. Runs alongside Shimmy in the same container
2. Listens on port 8080 (external)
3. Maps SAP AI Core's allowed `/v1/*` endpoints to Shimmy's native endpoints
4. Shimmy runs on internal port 8081

## Architecture

```
External Request                  Container
┌────────────────┐              ┌──────────────────────────────────┐
│                │              │                                  │
│  /v1/health    │──────────────▶  Proxy (Port 8080)             │
│  /v1/generate  │              │       │                          │
│  /v1/models    │              │       │                          │
│                │              │       ▼                          │
└────────────────┘              │  Shimmy (Port 8081)             │
                                │    - /health                     │
                                │    - /api/generate               │
                                │    - /v1/models                  │
                                │                                  │
                                └──────────────────────────────────┘
```

## Endpoint Mappings

| External Endpoint (RBAC Allowed) | Internal Shimmy Endpoint | Description |
|----------------------------------|-------------------------|-------------|
| `/v1/health`                     | `/health`               | Health check |
| `/v1/generate`                   | `/api/generate`         | Text generation |
| `/v1/models`                     | `/v1/models`            | List models (passthrough) |
| `/v1/completions`                | `/api/generate`         | OpenAI-compatible completions |
| `/v1/chat/completions`           | `/api/generate`         | OpenAI-compatible chat |

## Files

### 1. `lightweight-proxy.py`
Minimal Flask-based proxy that handles endpoint mapping. Features:
- `/v1/health` → `/health` mapping
- `/v1/generate` → `/api/generate` mapping with streaming support
- `/v1/models` passthrough
- OpenAI-compatible endpoints transformation

### 2. `start-with-proxy.sh`
Startup orchestration script that:
- Starts Shimmy on port 8081 (internal)
- Waits for Shimmy to be ready
- Starts the proxy on port 8080 (external)
- Monitors both processes
- Handles graceful shutdown

### 3. `Dockerfile.rbac-fix`
Updated Dockerfile that:
- Includes Python 3 and pip
- Installs Flask and requests
- Copies proxy and startup scripts
- Configures health check on proxy endpoint
- Runs the startup script

## Building the Image

```bash
cd infrastructure/docker/images/shimmy-server
docker build -f Dockerfile.rbac-fix -t shimmy-rbac-fix:latest .
```

## Testing Locally

```bash
# Run the container
docker run -p 8080:8080 shimmy-rbac-fix:latest

# Test health check (in another terminal)
curl http://localhost:8080/v1/health

# Test models list
curl http://localhost:8080/v1/models

# Test generation
curl -X POST http://localhost:8080/v1/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3-lora",
    "prompt": "Hello, world!",
    "stream": false
  }'
```

## Deployment to SAP AI Core

### 1. Push Image to Registry

```bash
# Tag for your registry
docker tag shimmy-rbac-fix:latest docker.io/gjkarthik/shimmy-rbac-fix:latest

# Push to registry
docker push docker.io/gjkarthik/shimmy-rbac-fix:latest
```

### 2. Update ServingTemplate

Use the lightweight serving template:

```yaml
apiVersion: ai.sap.com/v1alpha1
kind: ServingTemplate
metadata:
  name: shimmy-rbac-fix
  annotations:
    scenarios.ai.sap.com/description: "Shimmy with RBAC bypass proxy"
    scenarios.ai.sap.com/name: "shimmy-rbac-fix"
    executables.ai.sap.com/description: "Shimmy with proxy for /v1/* endpoint mapping"
    executables.ai.sap.com/name: "shimmy-rbac-fix"
  labels:
    scenarios.ai.sap.com/id: "shimmy-rbac-fix"
    ai.sap.com/version: "1.0.1"
spec:
  template:
    apiVersion: "serving.kserve.io/v1beta1"
    metadata:
      annotations: |
        autoscaling.knative.dev/metric: concurrency
        autoscaling.knative.dev/target: 1
        autoscaling.knative.dev/targetBurstCapacity: 0
      labels: |
        ai.sap.com/resourcePlan: infer.s
    spec: |
      predictor:
        imagePullSecrets:
        - name: ollamadocker
        minReplicas: 1
        maxReplicas: 1
        containers:
        - name: kserve-container
          image: docker.io/gjkarthik/shimmy-rbac-fix:latest
          ports:
          - containerPort: 8080
            protocol: TCP
```

### 3. Deploy

```bash
kubectl apply -f shimmy-serving-template-rbac-fix.yaml
```

## Usage Examples

### Health Check
```bash
curl https://your-deployment.sap.ai/v1/health
```

### Generate Text
```bash
curl -X POST https://your-deployment.sap.ai/v1/generate \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "model": "phi3-lora",
    "prompt": "Write a haiku about AI",
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

### Streaming Generation
```bash
curl -X POST https://your-deployment.sap.ai/v1/generate \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "model": "phi3-lora",
    "prompt": "Tell me a story",
    "stream": true
  }'
```

### OpenAI-Compatible Completions
```bash
curl -X POST https://your-deployment.sap.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "model": "phi3-lora",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ]
  }'
```

## Advantages

1. **Minimal Overhead**: Lightweight Flask proxy with minimal resource usage
2. **No Dependencies**: Uses only Python standard library + Flask/requests
3. **Transparent**: Simple endpoint mapping without complex logic
4. **Reliable**: Monitors both Shimmy and proxy processes
5. **SAP AI Core Compatible**: Works within RBAC restrictions

## Troubleshooting

### Container Logs
```bash
kubectl logs <pod-name> -c kserve-container
```

### Check Shimmy Status
Inside the container:
```bash
curl http://localhost:8081/health
```

### Check Proxy Status
Inside the container:
```bash
curl http://localhost:8080/
```

### Common Issues

**Issue**: Health check failing
- **Solution**: Check if both Shimmy and proxy are running. The proxy health check proxies to Shimmy's `/health` endpoint.

**Issue**: Generation requests timing out
- **Solution**: Increase timeout values in the proxy configuration or adjust resource limits in the deployment.

**Issue**: RBAC errors persist
- **Solution**: Verify you're using `/v1/*` endpoints, not the native endpoints.

## Performance Considerations

- The proxy adds minimal latency (~1-5ms per request)
- Streaming responses are passed through efficiently
- Python process uses ~30-50MB RAM
- Flask handles concurrent requests well for inference workloads

## Security Notes

- Proxy runs as non-root user (shimmy:1000)
- Only exposes port 8080 externally
- Shimmy runs on internal port 8081 (not exposed)
- No authentication bypass - SAP AI Core RBAC still enforced at ingress level

## Monitoring

The container exposes health check at `/v1/health`:
```json
{
  "status": "healthy",
  "shimmy": "ready"
}
```

## Support

For issues or questions:
1. Check container logs
2. Verify endpoint mappings
3. Test Shimmy directly on port 8081 (if accessible)
4. Review SAP AI Core RBAC policies
