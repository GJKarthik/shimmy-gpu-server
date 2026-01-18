#!/usr/bin/env python3
"""
SAP AI Core API Gateway Proxy for Shimmy
Maps SAP AI Core's expected /v1/* endpoints to Shimmy's native endpoints
Keeps /v1/models untouched, adds /v1/health and transforms /v1/chat/completions
"""

import time
import logging
from flask import Flask, request, jsonify, Response
import requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
SHIMMY_URL = "http://localhost:8080"

@app.route('/v1/health', methods=['GET'])
def v1_health():
    """Proxy /v1/health to Shimmy's /health endpoint"""
    try:
        logger.info("Proxying /v1/health to Shimmy /health")
        resp = requests.get(f"{SHIMMY_URL}/health", timeout=5)
        return resp.json(), resp.status_code
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({"status": "error", "message": str(e)}), 503

@app.route('/v1/completions', methods=['POST'])
@app.route('/v1/chat/completions', methods=['POST'])
def v1_completions():
    """
    Transform OpenAI-style requests to Shimmy's /api/generate format
    Supports both streaming and non-streaming responses
    """
    try:
        data = request.json
        logger.info(f"Received request for model: {data.get('model')}")
        
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
            "model": data.get("model", "phi3-lora"),
            "prompt": prompt,
            "stream": data.get("stream", False),
            "temperature": data.get("temperature", 0.7),
            "max_tokens": data.get("max_tokens", 512),
            "top_p": data.get("top_p", 1.0),
            "frequency_penalty": data.get("frequency_penalty", 0.0),
            "presence_penalty": data.get("presence_penalty", 0.0)
        }
        
        logger.info(f"Forwarding to Shimmy: {shimmy_request['model']}")
        
        # Handle streaming responses
        if shimmy_request.get("stream"):
            def generate():
                with requests.post(
                    f"{SHIMMY_URL}/api/generate",
                    json=shimmy_request,
                    stream=True,
                    timeout=300
                ) as resp:
                    for line in resp.iter_lines():
                        if line:
                            yield line + b'\n'
            
            return Response(generate(), mimetype='text/event-stream')
        
        # Non-streaming response
        resp = requests.post(
            f"{SHIMMY_URL}/api/generate",
            json=shimmy_request,
            timeout=300
        )
        
        # Transform Shimmy response to OpenAI format
        shimmy_resp = resp.json()
        
        # Handle both completion and chat completion formats
        if 'messages' in data:
            # Chat completion response
            openai_resp = {
                "id": f"chatcmpl-{hash(shimmy_resp.get('response', ''))}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": data.get("model", "phi3-lora"),
                "choices": [{
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": shimmy_resp.get("response", "")
                    },
                    "finish_reason": "stop"
                }],
                "usage": {
                    "prompt_tokens": shimmy_resp.get("prompt_eval_count", 0),
                    "completion_tokens": shimmy_resp.get("eval_count", 0),
                    "total_tokens": shimmy_resp.get("prompt_eval_count", 0) + shimmy_resp.get("eval_count", 0)
                }
            }
        else:
            # Text completion response
            openai_resp = {
                "id": f"cmpl-{hash(shimmy_resp.get('response', ''))}",
                "object": "text_completion",
                "created": int(time.time()),
                "model": data.get("model", "phi3-lora"),
                "choices": [{
                    "text": shimmy_resp.get("response", ""),
                    "index": 0,
                    "finish_reason": "stop"
                }]
            }
        
        logger.info("Successfully transformed and returned response")
        return jsonify(openai_resp), resp.status_code
        
    except Exception as e:
        logger.error(f"Completion request failed: {e}")
        return jsonify({
            "error": {
                "message": str(e),
                "type": "internal_error",
                "code": "proxy_error"
            }
        }), 500

@app.route('/v1/models', methods=['GET'])
def v1_models():
    """Pass through to Shimmy's existing /v1/models endpoint"""
    try:
        logger.info("Passing through /v1/models request")
        resp = requests.get(f"{SHIMMY_URL}/v1/models", timeout=5)
        return resp.json(), resp.status_code
    except Exception as e:
        logger.error(f"Models list failed: {e}")
        return jsonify({"error": str(e)}), 500

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
            logger.warning(f"Shimmy health check returned status {resp.status_code}")
            return jsonify({
                "status": "degraded",
                "proxy": "running",
                "shimmy": "unhealthy"
            }), 503
    except requests.exceptions.RequestException as e:
        logger.error(f"Shimmy backend unreachable: {e}")
        return jsonify({
            "status": "unhealthy",
            "proxy": "running",
            "shimmy": "unreachable",
            "error": str(e)
        }), 503

if __name__ == '__main__':
    logger.info("Starting SAP AI Core proxy on port 8000")
    logger.info(f"Forwarding to Shimmy at {SHIMMY_URL}")
    app.run(host='0.0.0.0', port=8000, threaded=True)
