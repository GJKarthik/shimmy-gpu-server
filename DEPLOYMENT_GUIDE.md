# Shimmy Inference Server - Complete Deployment Guide

This guide walks you through building and deploying the Shimmy inference server with the baked Gemma-2B-IT model.

## Prerequisites

1. **Docker Desktop** installed and running on macOS
2. **Model file** located at `/Users/karthikeyan/git/aModels/models/gemma-2b-it-gguf/gemma-2-2b-it-Q4_K_M.gguf`

## Step 1: Start Docker Desktop

Before building, ensure Docker Desktop is running:

```bash
# Check if Docker is running
docker ps

# If not running, start Docker Desktop from Applications
# Or use: open -a Docker
```

Wait until Docker Desktop is fully started (the whale icon in the menu bar stops animating).

## Step 2: Build the Docker Image

From the project root directory:

```bash
# Navigate to the project root
cd /Users/karthikeyan/git/aModels

# Build the image (this will take several minutes)
docker build -t shimmy-gemma-2b:latest \
  -f infrastructure/docker/images/shimmy-server/Dockerfile .
```

The build process will:
1. Download the Shimmy binary (~50MB)
2. Copy the Gemma model (~1.5GB)
3. Configure the server

**Expected build time**: 3-5 minutes (depending on your internet connection)

## Step 3: Verify the Image

```bash
# List Docker images
docker images | grep shimmy

# Expected output:
# shimmy-gemma-2b   latest   <image-id>   <time>   ~2GB
```

## Step 4: Run the Container

### Option A: Using Docker Run (Simple)

```bash
docker run -d \
  --name shimmy-inference-server \
  -p 8080:8080 \
  --memory=8g \
  --cpus=4 \
  shimmy-gemma-2b:latest
```

### Option B: Using Docker Compose (Recommended)

```bash
cd infrastructure/docker/images/shimmy-server
docker-compose up -d
```

## Step 5: Verify the Container is Running

```bash
# Check container status
docker ps | grep shimmy

# View logs
docker logs shimmy-inference-server

# Follow logs in real-time
docker logs -f shimmy-inference-server
```

Wait for the message: "Shimmy server started on 0.0.0.0:8080"

## Step 6: Test the Server

### Quick Health Check

```bash
curl http://localhost:8080/health
```

Expected response: `{"status":"ok"}`

### Run Full Test Suite

```bash
cd infrastructure/docker/images/shimmy-server
./test-inference.sh
```

The test script will:
- ✓ Verify health endpoint
- ✓ List available models
- ✓ Test simple completion
- ✓ Test chat completion
- ✓ Test code generation

### Manual API Tests

**List Models:**
```bash
curl http://localhost:8080/v1/models | jq
```

**Simple Completion:**
```bash
curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-2b-it",
    "prompt": "Explain what Docker is in one sentence:",
    "max_tokens": 50,
    "temperature": 0.7
  }' | jq
```

**Chat Completion:**
```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-2b-it",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is the capital of France?"}
    ],
    "max_tokens": 100,
    "temperature": 0.5
  }' | jq
```

## Step 7: Performance Testing

Test inference speed:

```bash
time curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-2b-it",
    "prompt": "Write a short story about AI:",
    "max_tokens": 200
  }' | jq
```

Expected performance on M2 MacBook Air:
- First token: ~1-2 seconds
- Tokens per second: 15-30 tok/s
- Total time for 200 tokens: ~8-15 seconds

## Step 8: Integration Examples

### Python Integration

```python
import requests

def query_shimmy(prompt: str, max_tokens: int = 100):
    url = "http://localhost:8080/v1/completions"
    payload = {
        "model": "gemma-2b-it",
        "prompt": prompt,
        "max_tokens": max_tokens,
        "temperature": 0.7
    }
    response = requests.post(url, json=payload)
    return response.json()["choices"][0]["text"]

# Test
result = query_shimmy("What is machine learning?")
print(result)
```

### JavaScript/Node.js Integration

```javascript
const fetch = require('node-fetch');

async function queryShimmy(prompt, maxTokens = 100) {
  const response = await fetch('http://localhost:8080/v1/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'gemma-2b-it',
      prompt: prompt,
      max_tokens: maxTokens,
      temperature: 0.7
    })
  });
  const data = await response.json();
  return data.choices[0].text;
}

// Test
queryShimmy('What is Docker?').then(console.log);
```

## Troubleshooting

### Issue: Docker daemon not running

**Solution:**
```bash
# Start Docker Desktop
open -a Docker

# Wait 30 seconds, then verify
docker ps
```

### Issue: Port 8080 already in use

**Solution:**
```bash
# Find what's using port 8080
lsof -i :8080

# Kill the process or use a different port
docker run -d --name shimmy-inference-server -p 8081:8080 shimmy-gemma-2b:latest
```

### Issue: Container exits immediately

**Check logs:**
```bash
docker logs shimmy-inference-server
```

**Common causes:**
- Model file not found (verify COPY path in Dockerfile)
- Insufficient memory (increase Docker memory limits)
- Port conflict (use different port)

### Issue: Slow inference

**Solutions:**
1. Increase CPU allocation:
   ```bash
   docker run -d --name shimmy --cpus=6 -p 8080:8080 shimmy-gemma-2b:latest
   ```

2. Increase memory:
   ```bash
   docker run -d --name shimmy --memory=12g -p 8080:8080 shimmy-gemma-2b:latest
   ```

3. Use a smaller model or reduce context size

### Issue: Model not loading

**Verify model exists:**
```bash
# Check model file
ls -lh /Users/karthikeyan/git/aModels/models/gemma-2b-it-gguf/

# Check inside container
docker exec shimmy-inference-server ls -lh /models/
```

## Monitoring

### View Real-time Stats

```bash
# Container stats
docker stats shimmy-inference-server

# Resource usage
docker exec shimmy-inference-server top
```

### Check Server Metrics

```bash
# If Shimmy exposes metrics endpoint
curl http://localhost:8080/metrics
```

## Stopping and Cleanup

### Stop the Container

```bash
docker stop shimmy-inference-server
```

### Start Again

```bash
docker start shimmy-inference-server
```

### Remove Container

```bash
docker rm -f shimmy-inference-server
```

### Remove Image

```bash
docker rmi shimmy-gemma-2b:latest
```

### Full Cleanup

```bash
# Stop and remove container
docker stop shimmy-inference-server
docker rm shimmy-inference-server

# Remove image
docker rmi shimmy-gemma-2b:latest

# Clean up Docker system (careful!)
docker system prune -a
```

## Production Deployment

For production use, consider:

1. **Use docker-compose** for easier management
2. **Set resource limits** appropriately
3. **Enable logging** to a file or logging service
4. **Monitor metrics** with Prometheus/Grafana
5. **Use HTTPS** with a reverse proxy (nginx/traefik)
6. **Implement rate limiting** to prevent abuse
7. **Set up health checks** for auto-restart
8. **Use persistent volumes** if model needs to be updated

Example production docker-compose.yml:

```yaml
version: '3.8'
services:
  shimmy:
    image: shimmy-gemma-2b:latest
    container_name: shimmy-production
    ports:
      - "8080:8080"
    environment:
      - SHIMMY_LOG_LEVEL=info
    deploy:
      resources:
        limits:
          cpus: '6'
          memory: 12G
        reservations:
          cpus: '4'
          memory: 8G
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

## Next Steps

1. ✅ Build and run the container
2. ✅ Test the inference endpoints
3. 📝 Integrate with your application
4. 📊 Monitor performance and resource usage
5. 🚀 Deploy to production environment

## Support

For issues or questions:
- Check Shimmy documentation: https://github.com/Michael-A-Kuykendall/shimmy
- Review Docker logs: `docker logs shimmy-inference-server`
- Check system resources: `docker stats`
