#!/usr/bin/env python3
"""
Lightweight Proxy for Shimmy - SAP AI Core RBAC Workaround
Maps /v1/* endpoints (allowed by RBAC) to Shimmy's native endpoints
- /v1/health -> Shimmy's /health
- /v1/generate -> Shimmy's /api/generate
- /v1/models -> Shimmy's /v1/models (passthrough)
"""

import logging
from flask import Flask, request, jsonify, Response
import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
SHIMMY_URL = "http://localhost:8081"  # Shimmy on internal port

@app.route('/v1/health', methods=['GET'])
def v1_health():
    """
    SAP AI Core health check endpoint
    Maps /v1/health (RBAC allowed) -> Shimmy's /health
    """
    try:
        logger.info("Proxying /v1/health to Shimmy /health")
        resp = requests.get(f"{SHIMMY_URL}/health", timeout=5)
        return resp.json(), resp.status_code
    except requests.exceptions.RequestException as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 503

@app.route('/v1/generate', methods=['POST'])
def v1_generate():
    """
    SAP AI Core generate endpoint
    Maps /v1/generate (RBAC allowed) -> Shimmy's /api/generate
    Supports both streaming and non-streaming responses
    """
    try:
        data = request.json
        logger.info(f"Proxying /v1/generate to Shimmy /api/generate for model: {data.get('model', 'unknown')}")
        
        # Check if streaming is requested
        is_stream = data.get('stream', False)
        
        if is_stream:
            # Handle streaming response
            def generate():
                try:
                    with requests.post(
                        f"{SHIMMY_URL}/api/generate",
                        json=data,
                        stream=True,
                        timeout=300
                    ) as resp:
                        for chunk in resp.iter_content(chunk_size=None):
                            if chunk:
                                yield chunk
                except Exception as e:
                    logger.error(f"Streaming error: {e}")
                    yield f'{{"error": "{str(e)}"}}\n'.encode()
            
            return Response(generate(), mimetype='application/x-ndjson')
        else:
            # Handle non-streaming response
            resp = requests.post(
                f"{SHIMMY_URL}/api/generate",
                json=data,
                timeout=300
            )
            return resp.json(), resp.status_code
            
    except requests.exceptions.RequestException as e:
        logger.error(f"Generate request failed: {e}")
        return jsonify({
            "error": str(e)
        }), 500
    except Exception as e:
        logger.error(f"Unexpected error in /v1/generate: {e}")
        return jsonify({
            "error": str(e)
        }), 500

@app.route('/v1/models', methods=['GET'])
def v1_models():
    """
    Models endpoint - direct passthrough to Shimmy's /v1/models
    This endpoint already works, included for completeness
    """
    try:
        logger.info("Proxying /v1/models to Shimmy")
        resp = requests.get(f"{SHIMMY_URL}/v1/models", timeout=5)
        return resp.json(), resp.status_code
    except requests.exceptions.RequestException as e:
        logger.error(f"Models list failed: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/v1/completions', methods=['POST'])
@app.route('/v1/chat/completions', methods=['POST'])
def v1_completions():
    """
    OpenAI-compatible completions endpoint
    Maps to Shimmy's /api/generate with format transformation
    """
    try:
        data = request.json
        logger.info(f"Proxying /v1/completions to Shimmy /api/generate")
        
        # Extract prompt from messages or direct prompt
        if 'messages' in data:
            # Chat completion format
            prompt = "\n".join([
                f"{msg.get('role', 'user')}: {msg.get('content', '')}"
                for msg in data.get('messages', [])
            ])
        else:
            # Direct prompt format
            prompt = data.get('prompt', '')
        
        # Transform to Shimmy format
        shimmy_request = {
            "model": data.get("model", ""),
            "prompt": prompt,
            "stream": data.get("stream", False),
            "temperature": data.get("temperature", 0.7),
            "max_tokens": data.get("max_tokens", 512),
        }
        
        # Forward to Shimmy
        resp = requests.post(
            f"{SHIMMY_URL}/api/generate",
            json=shimmy_request,
            timeout=300
        )
        
        # Return Shimmy's response (client can handle the format)
        return resp.json(), resp.status_code
        
    except Exception as e:
        logger.error(f"Completion request failed: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/', methods=['GET'])
def root():
    """Root endpoint for basic connectivity check"""
    return jsonify({
        "service": "Shimmy Lightweight Proxy",
        "status": "running",
        "version": "1.0.0",
        "endpoints": {
            "health": "/v1/health",
            "generate": "/v1/generate",
            "models": "/v1/models",
            "completions": "/v1/completions"
        }
    }), 200

if __name__ == '__main__':
    logger.info("=" * 70)
    logger.info("Starting Shimmy Lightweight Proxy for SAP AI Core RBAC Bypass")
    logger.info("Proxy listening on: 0.0.0.0:8080")
    logger.info(f"Forwarding to Shimmy at: {SHIMMY_URL}")
    logger.info("Mapped endpoints:")
    logger.info("  /v1/health   -> /health")
    logger.info("  /v1/generate -> /api/generate")
    logger.info("  /v1/models   -> /v1/models (passthrough)")
    logger.info("=" * 70)
    app.run(host='0.0.0.0', port=8080, threaded=True)
