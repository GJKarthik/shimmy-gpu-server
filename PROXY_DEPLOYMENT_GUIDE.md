# Shimmy OpenAI Proxy Deployment Guide

## Overview

This guide covers the updated Shimmy deployment with an OpenAI-compatible proxy wrapper that provides `/v1/*` endpoints required by SAP AI Core.

## Architecture

```
SAP AI Core Request (port 8000)
         ↓
   Flask Proxy Wrapper
         ↓ (transforms /v1/chat/completions → /v1/chat-completion)
   Shimmy Server (port 8080)
         ↓
   Phi-3-Mini Model (Q5_K GGUF)
```

## Components

### 1. Proxy Wrapper (`proxy-wrapper.py`)
- **Port**: 8000 (exposed to SAP AI Core)
- **Function**: Translates OpenAI API format to Shimmy's native format
- **Endpoints**:
  - `GET /v1/models` - Lists available models
  - `POST /v1/chat/completions` - Chat completion endpoint
  - `GET /health` - Health check

### 2. Shimmy Server
- **Port**: 8080 (internal)
- **Model**: phi3-lora (Phi-3-Mini-4K Q5_K)
- **Native Endpoint**: `/v1/chat-completion`

### 3. Startup Script (`start.sh`)
- Launches Shimmy server in background
- Starts proxy wrapper in foreground
- Ensures both processes run concurrently

## Docker Image

**Image**: `docker.io/gjkarthik/shimmy:latest`
**Tag**: `v1.1-proxy`
**Size**: ~2.7GB (includes model weights)

### Build Command
```bash
cd infrastructure/docker/images/shimmy-server
docker build --platform linux/amd64 \
  -t docker.io/gjkarthik/shimmy:latest \
  -t docker.io/gjkarthik/shimmy:v1.1-proxy .
```

### Push Command
```bash
docker push docker.io/gjkarthik/shimmy:latest
docker push docker.io/gjkarthik/shimmy:v1.1-proxy
```

## Deployment to SAP AI Core

### Prerequisites
1. Docker secret created for registry access
2. SAP AI Core CLI configured
3. Appropriate resource plan (e.g., `infer.m`)

### Step 1: Create Docker Registry Secret
```bash
kubectl create secret docker-registry ollamadocker \
  --docker-server=docker.io \
  --docker-username=<your-username> \
  --docker-password=<your-token> \
  --docker-email=<your-email> \
  -n <your-namespace>
```

### Step 2: Apply Serving Template
```bash
kubectl apply -f shimmy-serving-template.yaml
```

### Step 3: Create Configuration
Create a configuration YAML pointing to your scenario and resource plan.

### Step 4: Create Deployment
Use SAP AI Core UI or CLI to create a deployment from the configuration.

## Testing the Deployment

### Health Check
```bash
curl -X GET https://<deployment-url>/health
```

Expected response:
```json
{
  "status": "healthy",
  "shimmy_status": "healthy"
}
```

### List Models
```bash
curl -X GET https://<deployment-url>/v1/models
```

Expected response:
```json
{
  "object": "list",
  "data": [
    {
      "id": "phi3-lora",
      "object": "model",
      "created": 1234567890,
      "owned_by": "shimmy"
    }
  ]
}
```

### Chat Completion
```bash
curl -X POST https://<deployment-url>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3-lora",
    "messages": [
      {
        "role": "user",
        "content": "What is the capital of France?"
      }
    ],
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

Expected response structure:
```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "phi3-lora",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The capital of France is Paris."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 8,
    "total_tokens": 18
  }
}
```

## Port Configuration

- **Container Port 8000**: Proxy wrapper (SAP AI Core endpoint)
- **Container Port 8080**: Shimmy server (internal)
- **Service Port**: Automatically configured by KServe/Knative

## Resource Requirements

### Minimum
- **Memory**: 4Gi
- **CPU**: 2000m (2 cores)

### Limits
- **Memory**: 8Gi
- **CPU**: 4000m (4 cores)

## Scaling Configuration

- **Min Replicas**: 1
- **Max Replicas**: 3
- **Autoscaling Target**: 1 concurrent request
- **Target Burst Capacity**: 0

## Troubleshooting

### Issue: 404 Not Found on /v1/chat/completions
**Solution**: Ensure you're using the latest image with proxy wrapper (`v1.1-proxy` or `latest`)

### Issue: Connection Refused
**Solution**: 
1. Check pod logs: `kubectl logs <pod-name> -c kserve-container`
2. Verify both Shimmy and proxy are running
3. Check startup script execution

### Issue: Model Not Loading
**Solution**:
1. Verify model file exists at `/models/phi3-mini.gguf`
2. Check Shimmy logs for loading errors
3. Ensure sufficient memory allocation

### Issue: Slow Response Times
**Solution**:
1. Increase resource limits
2. Consider using a smaller quantization (Q4_K_M instead of Q5_K_M)
3. Enable GPU acceleration if available

## Logs

### View Combined Logs
```bash
kubectl logs -f <pod-name> -c kserve-container
```

You should see:
```
[Shimmy] Starting Shimmy inference server on port 8080...
[Shimmy] Model loaded: phi3-lora
[Proxy] Starting OpenAI proxy on port 8000...
[Proxy] Forwarding /v1/* to Shimmy at http://localhost:8080
```

## Advanced Configuration

### Custom Model
To use a different model, update the Dockerfile:
```dockerfile
RUN curl -fsSL -o ${MODEL_PATH}/phi3-mini.gguf \
    https://your-model-url/model.gguf
```

### Different Quantization
Replace the model URL with desired quantization level:
- Q4_K_M: Smaller, faster, slightly lower quality
- Q5_K_M: Balanced (default)
- Q8_0: Highest quality, larger, slower

### Environment Variables
Add to serving template as needed:
```yaml
env:
  - name: SHIMMY_PORT
    value: "8080"
  - name: LOG_LEVEL
    value: "debug"
```

## Security Considerations

1. **HTTPS**: SAP AI Core automatically provides HTTPS termination
2. **Authentication**: Configure via SAP AI Core deployment settings
3. **Rate Limiting**: Handled by SAP AI Core platform
4. **Secrets**: Use Kubernetes secrets for sensitive configuration

## Performance Tuning

### For Production
```yaml
resources:
  requests:
    memory: "8Gi"
    cpu: "4000m"
  limits:
    memory: "16Gi"
    cpu: "8000m"
```

### For Development/Testing
```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

## Monitoring

### Key Metrics
- Request latency (track via SAP AI Core metrics)
- Token generation speed
- Memory usage
- CPU utilization
- Concurrent requests

### Health Check Endpoints
- `/health` on port 8080 (Shimmy native)
- `/v1/models` on port 8000 (Proxy health indicator)

## Next Steps

1. Deploy to SAP AI Core using the serving template
2. Test with the provided curl commands
3. Monitor performance and adjust resources as needed
4. Consider implementing additional endpoints if required
5. Set up alerting for health check failures

## Support

For issues:
- Check pod logs first
- Verify proxy wrapper is translating correctly
- Test Shimmy directly on port 8080 if needed
- Refer to Shimmy documentation: https://github.com/Michael-A-Kuykendall/shimmy
