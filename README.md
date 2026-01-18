# Shimmy Inference Server with Gemma-2B-IT

This directory contains a Docker setup for running the Shimmy inference server with a baked-in Gemma-2B-IT model.

## Overview

Shimmy is a lightweight inference server for running GGUF models. This setup:
- Downloads the Shimmy binary from the official releases
- Bakes the Gemma-2-2b-it-Q4_K_M.gguf model into the image
- Exposes an OpenAI-compatible API endpoint

## Files

- `Dockerfile` - Multi-stage build for the Shimmy server
- `docker-compose.yml` - Docker Compose configuration for easy deployment
- `test-inference.sh` - Test script to validate the inference server
- `README.md` - This file

## Building the Image

From the project root directory:

```bash
cd infrastructure/docker/images/shimmy-server
docker-compose build
```

Or build directly with Docker:

```bash
docker build -t shimmy-gemma-2b:latest -f infrastructure/docker/images/shimmy-server/Dockerfile .
```

## Running the Server

### Using Docker Compose (Recommended)

```bash
cd infrastructure/docker/images/shimmy-server
docker-compose up -d
```

### Using Docker directly

```bash
docker run -d \
  --name shimmy-inference-server \
  -p 8080:8080 \
  shimmy-gemma-2b:latest
```

## Testing the Server

Once the container is running, test it with the provided script:

```bash
./test-inference.sh
```

Or manually test with curl:

```bash
# Health check
curl http://localhost:8080/health

# List models
curl http://localhost:8080/v1/models

# Simple completion
curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-2b-it",
    "prompt": "Hello, how are you?",
    "max_tokens": 50,
    "temperature": 0.7
  }'

# Chat completion
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-2b-it",
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ],
    "max_tokens": 100
  }'
```

## Model Details

- **Model**: Gemma-2-2B-IT (Instruction Tuned)
- **Format**: GGUF (Q4_K_M quantization)
- **Context Size**: 8192 tokens
- **Architecture**: LLaMA-based

## API Endpoints

The server exposes OpenAI-compatible endpoints:

- `GET /health` - Health check endpoint
- `GET /v1/models` - List available models
- `POST /v1/completions` - Text completion endpoint
- `POST /v1/chat/completions` - Chat completion endpoint

## Resource Requirements

- **CPU**: 2-4 cores recommended
- **Memory**: 4-8 GB RAM recommended
- **Disk**: ~2 GB for model + image

## Stopping the Server

```bash
# With Docker Compose
docker-compose down

# With Docker
docker stop shimmy-inference-server
docker rm shimmy-inference-server
```

## Troubleshooting

### Server not starting

Check logs:
```bash
docker logs shimmy-inference-server
```

### Out of memory

Increase Docker memory limits or reduce model context size.

### Slow inference

- Consider using a CPU with AVX2 support
- Reduce batch size or context length
- Use a smaller quantization (Q4_K_M is already quite efficient)

## References

- [Shimmy GitHub](https://github.com/Michael-A-Kuykendall/shimmy)
- [Gemma Models](https://ai.google.dev/gemma)
- [GGUF Format](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)
