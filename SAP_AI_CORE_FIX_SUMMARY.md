# SAP AI Core Deployment Fix - Summary

## The Actual Problem

You reported: **"deployment got stuck at `GET /health HTTP/1.1" 200 -`"**

The health check was **succeeding** (200 response), but the deployment wasn't progressing to Ready state.

### Root Cause

**Port mismatch in health probe configuration:**
- Container exposes port **8000** (proxy with OpenAI-compatible API)
- SAP AI Core ServingTemplate was checking health on port **8080** (Shimmy's internal port)
- Since port 8080 wasn't exposed externally, health checks couldn't reach it from SAP AI Core

## The Simple Fix

Since Shimmy already exposes `/health` and the proxy forwards it properly, we just needed to update the ServingTemplate to check the correct port.

### Changes Made

1. **Updated `shimmy-serving-template.yaml`**:
   - Changed health probe port from `8080` → `8000`
   - Added startup probe for longer initialization time
   - Increased initial delays to account for model loading

2. **Enhanced `proxy-wrapper.py`**:
   - Added comprehensive `/health` endpoint that validates both proxy and Shimmy backend
   - Returns detailed health status for better debugging

3. **Improved `start.sh`**:
   - Added retry logic to ensure Shimmy is fully ready before starting proxy
   - Better error handling and logging

## Quick Fix Guide

### If You Just Need the Template Fix

Update your `shimmy-serving-template.yaml`:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000  # Changed from 8080
  initialDelaySeconds: 60
  periodSeconds: 30
  
readinessProbe:
  httpGet:
    path: /health
    port: 8000  # Changed from 8080
  initialDelaySeconds: 60
  periodSeconds: 10
  
startupProbe:  # NEW
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 12  # Allows up to 120s for startup
```

### Rebuild and Redeploy

```bash
# 1. Rebuild image with fixes
cd infrastructure/docker/images/shimmy-server
docker build -t gjkarthik/shimmy:latest .
docker push gjkarthik/shimmy:latest

# 2. Update SAP AI Core deployment
kubectl apply -f shimmy-serving-template.yaml

# 3. Create new deployment in SAP AI Core UI
# The deployment should now progress past health checks
```

## What Each Component Does

### Port Architecture

```
External Request → Port 8000 (Proxy) → Port 8080 (Shimmy)
                       ↓
                  /health checks Shimmy backend
                  /v1/chat/completions transforms to Shimmy API
                  /v1/models passes through
```

### Health Check Flow

1. SAP AI Core checks `http://container:8000/health`
2. Proxy receives request, forwards to `http://localhost:8080/health`
3. Shimmy responds with health status
4. Proxy returns combined status to SAP AI Core
5. SAP AI Core marks pod as Ready ✅

## Verification Steps

After redeployment, verify:

```bash
# 1. Check pod is running
kubectl get pods -n <namespace>

# 2. Check logs show both services started
kubectl logs <pod-name> | grep "System"
# Should see: "[System] Health endpoints available at both ports"

# 3. Test health endpoint
kubectl port-forward <pod-name> 8000:8000
curl http://localhost:8000/health
# Should return: {"status": "healthy", "proxy": "running", "shimmy": "ready"}

# 4. Test inference
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "phi3-mini", "messages": [{"role": "user", "content": "test"}]}'
```

## Why This Fix Works

1. **Correct Port**: Health checks now target the externally exposed port (8000)
2. **Backend Validation**: Proxy verifies Shimmy is actually ready before reporting healthy
3. **Startup Probe**: Gives container up to 120 seconds to load model without failing
4. **Proper Sequencing**: start.sh ensures Shimmy is ready before starting proxy

## Files Modified

1. ✅ `shimmy-serving-template.yaml` - Fixed health probe ports
2. ✅ `proxy-wrapper.py` - Enhanced /health endpoint
3. ✅ `start.sh` - Added startup validation
4. ✅ `Dockerfile` - Already correct (no changes needed)

## Next Steps

1. Build and push updated image
2. Update ServingTemplate in SAP AI Core
3. Create new deployment
4. Monitor logs to confirm successful startup
5. Test inference endpoints

The deployment should now progress successfully past the health check stage!
