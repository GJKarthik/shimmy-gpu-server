# SAP AI Core Health Check Fix

## Problem Identified

The Shimmy deployment was getting stuck at `GET /health HTTP/1.1" 200 -` due to a **health check endpoint mismatch**:

### Root Causes

1. **Port Mismatch**: 
   - SAP AI Core health probes were checking port 8080 (Shimmy's internal port)
   - External access should use port 8000 (proxy port)

2. **Missing Health Endpoint**:
   - Proxy only exposed `/v1/health` but not `/health`
   - SAP AI Core expects a standard `/health` endpoint

3. **Startup Timing Issues**:
   - No proper health check validation before starting proxy
   - No startup probe to allow longer initialization time

## Solutions Implemented

### 1. Enhanced Proxy Health Endpoint (`proxy-wrapper.py`)

Added comprehensive `/health` endpoint on port 8000 that:
- Checks proxy status
- Validates Shimmy backend connectivity
- Returns proper HTTP status codes (200/503)
- Provides detailed health information

```python
@app.route('/health', methods=['GET'])
def health():
    """
    Comprehensive health check for SAP AI Core
    Checks both proxy and Shimmy backend availability
    """
    try:
        # Check if Shimmy backend is responding
        resp = requests.get(f"{SHIMMY_URL}/health", timeout=2)
        if resp.status_code == 200:
            return jsonify({
                "status": "healthy",
                "proxy": "running",
                "shimmy": "ready",
                "timestamp": int(time.time())
            }), 200
        else:
            return jsonify({
                "status": "degraded",
                "proxy": "running",
                "shimmy": "unhealthy"
            }), 503
    except requests.exceptions.RequestException as e:
        return jsonify({
            "status": "unhealthy",
            "proxy": "running",
            "shimmy": "unreachable",
            "error": str(e)
        }), 503
```

### 2. Improved Startup Script (`start.sh`)

Enhanced startup sequence with:
- Retry logic for Shimmy health checks (30 retries, 2s intervals)
- Proxy health validation before declaring ready
- Better logging for debugging
- Proper error handling and timeouts

Key improvements:
```bash
# Wait for Shimmy with retries
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

# Wait for proxy to be ready
until curl -f http://localhost:8000/health > /dev/null 2>&1; do
    echo "[Proxy] Waiting for proxy health endpoint..."
    sleep 1
done
```

### 3. Updated ServingTemplate (`shimmy-serving-template.yaml`)

Fixed health probe configuration:

**Before:**
- Health checks on port 8080 (internal Shimmy port)
- Short initial delays (30s)
- No startup probe

**After:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000          # Changed to proxy port
  initialDelaySeconds: 60  # Increased for model loading
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health
    port: 8000          # Changed to proxy port
  initialDelaySeconds: 60  # Increased for model loading
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

startupProbe:            # NEW: Allows up to 120s for startup
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 12   # 12 * 10s = 120s total
```

## Deployment Steps

### 1. Rebuild Docker Image

```bash
cd infrastructure/docker/images/shimmy-server
docker build -t gjkarthik/shimmy:latest .
docker push gjkarthik/shimmy:latest
```

### 2. Update SAP AI Core Deployment

```bash
# Delete existing deployment (if any)
kubectl delete -f shimmy-serving-template.yaml

# Apply updated template
kubectl apply -f shimmy-serving-template.yaml

# Create new deployment
# Use SAP AI Core UI or CLI to create deployment from updated template
```

### 3. Monitor Deployment

```bash
# Check pod status
kubectl get pods -n <your-namespace>

# View logs
kubectl logs -f <shimmy-pod-name> -n <your-namespace>

# Check health endpoint
kubectl port-forward <shimmy-pod-name> 8000:8000 -n <your-namespace>
curl http://localhost:8000/health
```

## Expected Health Check Response

### Healthy State
```json
{
  "status": "healthy",
  "proxy": "running",
  "shimmy": "ready",
  "timestamp": 1705318800
}
```

### Degraded State (Shimmy not ready)
```json
{
  "status": "degraded",
  "proxy": "running",
  "shimmy": "unhealthy"
}
```

### Unhealthy State (Shimmy unreachable)
```json
{
  "status": "unhealthy",
  "proxy": "running",
  "shimmy": "unreachable",
  "error": "Connection refused"
}
```

## Testing Locally

Test the fixes locally before deploying to SAP AI Core:

```bash
# Start container
docker run -p 8000:8000 gjkarthik/shimmy:latest

# In another terminal, test health endpoint
curl http://localhost:8000/health

# Test inference
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3-mini",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'
```

## Troubleshooting

### Deployment Still Stuck at Health Check

1. **Check pod logs:**
   ```bash
   kubectl logs <pod-name> -n <namespace>
   ```

2. **Verify health endpoint directly:**
   ```bash
   kubectl port-forward <pod-name> 8000:8000
   curl -v http://localhost:8000/health
   ```

3. **Check resource availability:**
   - Ensure GPU is available: `nvidia.com/gpu: "1"`
   - Verify memory limits: 4-8Gi
   - Check CPU allocation: 2-4 cores

### Health Check Returns 503

- Shimmy backend may still be loading the model
- Increase `initialDelaySeconds` in probes
- Check if model file is accessible: `/models/phi3-mini.gguf`

### Connection Refused Errors

- Ensure both services (Shimmy + Proxy) are running
- Check start.sh logs for startup sequence issues
- Verify port bindings: 8080 (Shimmy), 8000 (Proxy)

## Benefits of This Fix

1. **Proper Health Monitoring**: SAP AI Core can accurately determine service readiness
2. **Startup Probe**: Allows sufficient time for model loading without failing health checks
3. **Backend Validation**: Health check verifies both proxy and Shimmy backend
4. **Better Debugging**: Detailed health status helps identify issues quickly
5. **Production Ready**: Robust error handling and timeout management

## Next Steps

After successful deployment:

1. Monitor the deployment for 10-15 minutes
2. Verify inference works via `/v1/chat/completions`
3. Check autoscaling behavior under load
4. Set up alerting on health check failures
5. Document any SAP AI Core-specific configuration needs
