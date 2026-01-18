# Shimmy Dynamic Model Download - IMPLEMENTATION SUCCESS ✅

## Status: FULLY OPERATIONAL

Successfully implemented automatic model download with discovery and server restart for Shimmy in Kubernetes!

## Docker Image

**Production Image**: `docker.io/gjkarthik/shimmy:latest` (also tagged as `v2.5-sigterm-fix`)
- **Platforms**: `linux/amd64`, `linux/arm64`
- **Size**: ~500MB
- **Built**: January 17, 2026

## Implementation Journey

### Evolution Through Versions

| Version | Changes | Issue | Status |
|---------|---------|-------|--------|
| v2.2 | Fixed model path (`SHIMMY_MODEL_PATH=/models`) | Wrong path | ✅ Fixed |
| v2.3 | Added server restart with SIGHUP | Shimmy terminated | ❌ Failed |
| v2.4 | Added `procps` package for pgrep | Still using SIGHUP | ❌ Failed |
| v2.5 | **Changed to SIGTERM for restart** | - | ✅ **WORKING** |

### Key Fix (v2.5)

**Problem**: Shimmy doesn't support hot-reload signals - SIGHUP/SIGUSR1 cause termination

**Solution**: Use SIGTERM + automatic restart by monitoring script

```python
# OLD (v2.3-v2.4): Killed the process
subprocess.run(['kill', '-HUP', str(pid)])

# NEW (v2.5): Graceful termination + auto-restart
subprocess.run(['kill', '-TERM', str(pid)])
logger.info("SIGTERM sent to Shimmy server - start script will restart with new models")
```

The `start-with-downloader.sh` script monitors the Shimmy process and automatically restarts it when it terminates.

## Features

### 1. Model Download API ✅

Download GGUF models from HuggingFace Hub:

```bash
curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF",
    "filename": "tinyllama-1.1b-chat-v1.0.Q2_K.gguf"
  }'
```

**Response** (streaming):
```json
{"status": "starting", "model": "...", "filename": "..."}
{"status": "complete", "filename": "...", "path": "/models/...", "size_mb": 460.74, "discovered": true}
```

### 2. Automatic Model Discovery ✅

After download completes:
1. Runs `shimmy discover` to scan `/models` directory
2. Registers new models in Shimmy's registry
3. Models immediately available in `/v1/models` endpoint

### 3. Automatic Server Restart ✅

The workflow:
1. Download completes → File validated as GGUF ✅
2. Run `shimmy discover` → Model registered ✅
3. Find Shimmy serve PID → Using `pgrep` ✅
4. Send SIGTERM → Graceful termination ✅
5. Start script detects termination → Restarts Shimmy ✅
6. New Shimmy instance loads all models ✅

## Complete Workflow

```
User Request
    ↓
POST /v1/api/pull
    ↓
1. Download from HuggingFace → /models/filename.gguf
    ↓
2. Validate GGUF format ✅
    ↓
3. Run: shimmy discover
    ↓
   Output: ✅ Found 1 models:
     tinyllama-1.1b-chat-v1.0.q2-k [460MB]
    ↓
4. Find PID: pgrep -f 'shimmy serve'  
    ↓
5. Terminate: kill -TERM <PID>
    ↓
6. start-with-downloader.sh detects exit
    ↓
7. Restarts: shimmy serve --bind 0.0.0.0:8081 --model-path /models
    ↓
8. All models (old + new) now available!
    ↓
GET /v1/models → Returns all models including new one ✅
```

## Deployment

### Current Status

```bash
# Check deployment
$ kubectl get pods -n kube-scb -l app=shimmy-model-downloader
NAME                                      READY   STATUS    RESTARTS   AGE
shimmy-model-downloader-7865d5769-kdvfm   2/2     Running   0          5m

# Verify v2.5 is running
$ kubectl exec -n kube-scb $POD -c shimmy -- grep "SIGTERM" /app/model-downloader-proxy.py
                # Send SIGTERM to gracefully terminate - the start script will restart it
                subprocess.run(['kill', '-TERM', str(pid)], timeout=2)
```

### Kubernetes Configuration

**Deployment**: `infrastructure/kyma/shimmy-test/deployment-with-pull.yaml`
- Image: `docker.io/gjkarthik/shimmy:latest`
- ImagePullPolicy: `Always`
- Replicas: 1
- Resources: 4 CPU, 8Gi RAM

**Service**: `infrastructure/kyma/shimmy-test/service-with-pull.yaml`
- Name: `shimmy-model-downloader`
- Port: 8080 (external) → 8080 (proxy) → 8081 (shimmy)

## Usage Examples

### 1. Download a Small Model (TinyLlama 460MB)

```bash
kubectl port-forward -n kube-scb svc/shimmy-model-downloader 8080:8080 &

curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF",
    "filename": "tinyllama-1.1b-chat-v1.0.Q2_K.gguf"
  }'

# Wait ~30 seconds for server restart
sleep 30

# Verify model appears
curl http://localhost:8080/v1/models | jq '.data[] | select(.id | contains("tiny"))'
```

### 2. Download a Larger Model (Phi-2 1.1GB)

```bash
curl -X POST http://localhost:8080/v1/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "model": "microsoft/phi-2-GGUF",  
    "filename": "phi-2.Q2_K.gguf"
  }'
```

### 3. Test Inference

```bash
curl -X POST http://localhost:8080/v1/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tinyllama-1.1b-chat-v1.0.q2-k",
    "prompt": "Hello! Introduce yourself.",
    "stream": false,
    "max_tokens": 50
  }' | jq '.response'
```

## API Endpoints

All endpoints exposed on port 8080:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Service info & status |
| `/v1/health` | GET | Health check (SAP AI Core compatible) |
| `/v1/models` | GET | List all available models |
| `/v1/generate` | POST | Text generation |
| `/v1/completions` | POST | OpenAI-compatible completions |
| `/v1/api/pull` | POST | **Download models from HuggingFace** |

## Files Modified/Created

### Core Implementation

1. **`model-downloader-proxy.py`** - Enhanced proxy with download API
   - HuggingFace integration
   - GGUF validation  
   - Automatic discovery
   - SIGTERM restart (v2.5 fix)

2. **`start-with-downloader.sh`** - Startup script
   - Monitors Shimmy process
   - Auto-restarts on termination
   - Health checks

3. **`Dockerfile.rbac-fix-with-pull`** - Production Dockerfile
   - Multi-arch build
   - Includes `procps` for pgrep
   - Python dependencies (flask, requests, huggingface_hub)

### Deployment Files

4. **`infrastructure/kyma/shimmy-test/deployment-with-pull.yaml`**
5. **`infrastructure/kyma/shimmy-test/service-with-pull.yaml`**

### Documentation

6. **`MODEL_DOWNLOAD_GUIDE.md`** - Usage guide
7. **`DYNAMIC_MODEL_DOWNLOAD_SUCCESS.md`** - This file!

## Testing Results

### ✅ All Components Verified

- [x] Download API responds
- [x] HuggingFace integration works
- [x] GGUF validation working
- [x] Model discovery succeeds
- [x] PID finding works (pgrep)
- [x] SIGTERM termination successful
- [x] Server auto-restart working
- [x] Models appear in /v1/models
- [x] Inference working

### Test Log Example

```
=== Step 1: Check current models ===
"models"
"phi3-lora"

=== Step 2: Download TinyLlama (460MB) ===
{"status": "starting", ...}
{"status": "complete", "size_mb": 460.74, "discovered": true}

=== Step 3: Wait for restart (15s) ===

=== Step 4: Model now available ===
{
  "id": "tinyllama-1.1b-chat-v1.0.q2-k",
  "object": "model",
  "owned_by": "shimmy"
}
```

## Known Limitations

1. **Ephemeral Storage**: `/models` directory is not persistent
   - Models are lost when pod restarts
   - **Solution**: Add PersistentVolumeClaim for production use

2. **Restart Downtime**: ~15-30 seconds during model loading
   - Server unavailable during restart
   - **Acceptable** for model management operations

3. **Single Download**: Only one download at a time
   - Protected by `download_lock` in proxy
   - Subsequent requests return 409 Conflict

## Production Considerations

### Persistent Storage (Recommended)

Add a PVC for `/models`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shimmy-models
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi  # Adjust based on model sizes
```

Update deployment:
```yaml
volumes:
  - name: models
    persistentVolumeClaim:
      claimName: shimmy-models
volumeMounts:
  - name: models
    mountPath: /models
```

### Model Size Planning

| Model Type | Size | Recommended Storage |
|------------|------|---------------------|
| Tiny (Q2_K) | 400-500MB | 10Gi |
| Small (Q4_K_M) | 1-2GB | 20Gi |
| Medium (Q5_K_M) | 3-5GB | 30Gi |
| Large (Q8_0) | 7-10GB | 50Gi |

### Monitoring

Monitor these metrics:
- Download duration
- Server restart time
- Model discovery success rate
- Inference latency after new model addition

## Troubleshooting

### Model doesn't appear after download

**Check**: Wait 30 seconds for server restart to complete

```bash
# Check if server restarted
kubectl logs -n kube-scb $POD -c shimmy --tail=20 | grep "Starting Shimmy"

# Verify model file exists
kubectl exec -n kube-scb $POD -c shimmy -- ls -lh /models/
```

### Download fails

**Check**: HuggingFace model repository and filename

```bash
# Verify repository exists
curl https://huggingface.co/api/models/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF

# Check available files
curl https://huggingface.co/api/models/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/tree/main
```

### Server won't restart

**Check**: Start script logs

```bash
kubectl logs -n kube-scb $POD -c shimmy | grep -E "(ERROR|restart|Terminated)"
```

## Success Metrics

✅ **Implementation Complete**: 100%
✅ **All Features Working**: Yes
✅ **Production Ready**: Yes (with persistent storage)
✅ **Documentation Complete**: Yes

## Next Steps

1. **Add Persistent Storage** - For production deployment
2. **Add Model Catalog** - List of pre-approved models
3. **Add Progress UI** - Web interface for model management
4. **Add Model Deletion** - API to remove models

## Conclusion

The Shimmy dynamic model download feature is **fully operational** with v2.5! The SIGTERM fix resolved the server restart issue, and all components are working as designed:

- ✅ Download from HuggingFace
- ✅ Automatic discovery
- ✅ Server restart
- ✅ Models immediately usable

**Docker Image**: `docker.io/gjkarthik/shimmy:latest` (v2.5-sigterm-fix)

Ready for production use with persistent storage! 🎉
