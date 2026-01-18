#!/usr/bin/env python3
"""
Enhanced Proxy for Shimmy with Model Download Support
- All original endpoints from lightweight-proxy.py
- New /v1/api/pull endpoint for downloading GGUF models from HuggingFace
"""

import logging
import os
import threading
import subprocess
from pathlib import Path
from flask import Flask, request, jsonify, Response, stream_with_context
import requests
from huggingface_hub import hf_hub_download, HfFileMetadata, hf_hub_url
from huggingface_hub.utils import HfHubHTTPError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
SHIMMY_URL = "http://localhost:8081"
MODELS_DIR = "/models"

# Download state management
download_lock = threading.Lock()
current_download = {
    "in_progress": False,
    "model": None,
    "filename": None
}

def check_gguf_file(filepath):
    """Verify that the downloaded file is a valid GGUF file"""
    try:
        with open(filepath, 'rb') as f:
            magic = f.read(4)
            # GGUF magic number is 'GGUF' (0x46554747)
            return magic == b'GGUF' or magic == b'GGML'  # Support both GGUF and older GGML
    except Exception as e:
        logger.error(f"Failed to verify GGUF file: {e}")
        return False

def trigger_shimmy_discover_and_restart():
    """Trigger Shimmy to discover new models and restart the Shimmy server process"""
    try:
        # Run shimmy discover
        result = subprocess.run(
            ['shimmy', 'discover'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            logger.info(f"Shimmy discover completed: {result.stdout}")
        else:
            logger.error(f"Shimmy discover failed: {result.stderr}")
            return False
        
        # Find and restart Shimmy server process
        # Look for the shimmy serve process
        try:
            find_proc = subprocess.run(
                ['pgrep', '-f', 'shimmy serve'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if find_proc.returncode == 0 and find_proc.stdout.strip():
                pid = int(find_proc.stdout.strip().split('\n')[0])
                logger.info(f"Found Shimmy serve process (PID: {pid}), terminating for restart...")
                # Send SIGTERM to gracefully terminate - the start script will restart it
                subprocess.run(['kill', '-TERM', str(pid)], timeout=2)
                logger.info("SIGTERM sent to Shimmy server - start script will restart with new models")
                return True
            else:
                logger.warning("Could not find Shimmy serve process, models may not be available until restart")
                return True  # Discovery still succeeded
        except Exception as e:
            logger.warning(f"Failed to terminate Shimmy process: {e}")
            return True  # Discovery still succeeded
            
    except Exception as e:
        logger.error(f"Failed to run shimmy discover: {e}")
        return False

@app.route('/v1/api/pull', methods=['POST'])
def pull_model():
    """
    Download a GGUF model from HuggingFace
    Request body: {
        "model": "TheBloke/phi-3-mini-4k-instruct-GGUF",
        "filename": "phi-3-mini-4k-instruct.Q4_K_M.gguf"
    }
    """
    try:
        data = request.json
        if not data:
            return jsonify({"status": "error", "error": "Request body required"}), 400
        
        model_repo = data.get('model')
        filename = data.get('filename')
        
        if not model_repo or not filename:
            return jsonify({
                "status": "error",
                "error": "Both 'model' and 'filename' are required"
            }), 400
        
        # Check if download already in progress
        with download_lock:
            if current_download["in_progress"]:
                return jsonify({
                    "status": "error",
                    "error": f"Download already in progress: {current_download['model']}/{current_download['filename']}"
                }), 409
            
            # Mark download as in progress
            current_download["in_progress"] = True
            current_download["model"] = model_repo
            current_download["filename"] = filename
        
        def generate():
            """Stream download progress"""
            try:
                # Send starting message
                yield f'{{"status": "starting", "model": "{model_repo}", "filename": "{filename}"}}\n'
                logger.info(f"Starting download: {model_repo}/{filename}")
                
                # Ensure models directory exists
                os.makedirs(MODELS_DIR, exist_ok=True)
                
                # Download file from HuggingFace
                # Note: hf_hub_download shows progress on stderr by default
                # For simplicity, we'll download and then report completion
                local_path = hf_hub_download(
                    repo_id=model_repo,
                    filename=filename,
                    cache_dir=None,
                    local_dir=MODELS_DIR,
                    local_dir_use_symlinks=False
                )
                
                # Verify it's a GGUF file
                if not check_gguf_file(local_path):
                    os.remove(local_path)
                    yield f'{{"status": "error", "error": "Downloaded file is not a valid GGUF/GGML model"}}\n'
                    return
                
                # Get file size
                file_size = os.path.getsize(local_path)
                size_mb = round(file_size / (1024 * 1024), 2)
                
                # Trigger Shimmy to discover the new model and restart server
                logger.info("Triggering shimmy discover and server reload for new model...")
                discover_success = trigger_shimmy_discover_and_restart()
                
                # Send completion message
                yield f'{{"status": "complete", "filename": "{filename}", "path": "{local_path}", "size_mb": {size_mb}, "discovered": {str(discover_success).lower()}}}\n'
                logger.info(f"Download complete: {local_path} ({size_mb} MB), Model discovery: {'success' if discover_success else 'failed'}")
                
            except HfHubHTTPError as e:
                error_msg = f"HuggingFace error: {str(e)}"
                logger.error(error_msg)
                yield f'{{"status": "error", "error": "{error_msg}"}}\n'
            except Exception as e:
                error_msg = f"Download failed: {str(e)}"
                logger.error(error_msg)
                yield f'{{"status": "error", "error": "{error_msg}"}}\n'
            finally:
                # Release lock
                with download_lock:
                    current_download["in_progress"] = False
                    current_download["model"] = None
                    current_download["filename"] = None
        
        return Response(stream_with_context(generate()), mimetype='application/x-ndjson')
        
    except Exception as e:
        # Make sure to release lock on any error
        with download_lock:
            current_download["in_progress"] = False
            current_download["model"] = None
            current_download["filename"] = None
        logger.error(f"Error in pull_model: {e}")
        return jsonify({"status": "error", "error": str(e)}), 500

@app.route('/v1/health', methods=['GET'])
def v1_health():
    """SAP AI Core health check endpoint"""
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
    """SAP AI Core generate endpoint"""
    try:
        data = request.json
        logger.info(f"Proxying /v1/generate to Shimmy /api/generate for model: {data.get('model', 'unknown')}")
        
        is_stream = data.get('stream', False)
        
        if is_stream:
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
            resp = requests.post(
                f"{SHIMMY_URL}/api/generate",
                json=data,
                timeout=300
            )
            return resp.json(), resp.status_code
            
    except requests.exceptions.RequestException as e:
        logger.error(f"Generate request failed: {e}")
        return jsonify({"error": str(e)}), 500
    except Exception as e:
        logger.error(f"Unexpected error in /v1/generate: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/v1/models', methods=['GET'])
def v1_models():
    """Models endpoint - passthrough to Shimmy"""
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
    """OpenAI-compatible completions endpoint"""
    try:
        data = request.json
        logger.info(f"Proxying /v1/completions to Shimmy /api/generate")
        
        if 'messages' in data:
            prompt = "\n".join([
                f"{msg.get('role', 'user')}: {msg.get('content', '')}"
                for msg in data.get('messages', [])
            ])
        else:
            prompt = data.get('prompt', '')
        
        shimmy_request = {
            "model": data.get("model", ""),
            "prompt": prompt,
            "stream": data.get("stream", False),
            "temperature": data.get("temperature", 0.7),
            "max_tokens": data.get("max_tokens", 512),
        }
        
        resp = requests.post(
            f"{SHIMMY_URL}/api/generate",
            json=shimmy_request,
            timeout=300
        )
        
        return resp.json(), resp.status_code
        
    except Exception as e:
        logger.error(f"Completion request failed: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/', methods=['GET'])
def root():
    """Root endpoint for basic connectivity check"""
    return jsonify({
        "service": "Shimmy Enhanced Proxy with Model Download",
        "status": "running",
        "version": "2.0.0",
        "endpoints": {
            "health": "/v1/health",
            "generate": "/v1/generate",
            "models": "/v1/models",
            "completions": "/v1/completions",
            "pull": "/v1/api/pull"
        },
        "download_status": {
            "in_progress": current_download["in_progress"],
            "current_model": current_download["model"],
            "current_filename": current_download["filename"]
        }
    }), 200

if __name__ == '__main__':
    logger.info("=" * 70)
    logger.info("Starting Shimmy Enhanced Proxy with Model Download Support")
    logger.info("Proxy listening on: 0.0.0.0:8080")
    logger.info(f"Forwarding to Shimmy at: {SHIMMY_URL}")
    logger.info(f"Models directory: {MODELS_DIR}")
    logger.info("Endpoints:")
    logger.info("  /v1/health     -> /health")
    logger.info("  /v1/generate   -> /api/generate")
    logger.info("  /v1/models     -> /v1/models")
    logger.info("  /v1/api/pull   -> Download GGUF models from HuggingFace")
    logger.info("=" * 70)
    app.run(host='0.0.0.0', port=8080, threaded=True)
