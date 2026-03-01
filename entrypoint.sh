#!/bin/bash
set -e

# =============================================================================
# TensorRT-LLM v0.18.0 Entrypoint for SAP AI Core
# Uses pre-converted checkpoint (INT4 AWQ + INT8 KV cache) - NO CONVERSION NEEDED
# =============================================================================

# --- Configuration (Overridden by ServingTemplate Env Vars) ---
# Pre-converted TRT-LLM checkpoint (INT4 AWQ + INT8 KV)
CHECKPOINT_MODEL=${MODEL:-"rungalileo/mistral-7b-instruct-v0.3-trtllm-ckpt-wq_int4_awq-kv_int8"}
# Base model for tokenizer
TOKENIZER_MODEL=${TOKENIZER:-"mistralai/Mistral-7B-Instruct-v0.3"}

# Build configuration - T4 GPU has only 16GB VRAM, reduce settings to fit
# Original settings (8 batch, 4096 input, 8192 seq) require ~24.5GB scratch space
# Reduced settings to fit within T4's 16GB memory
MAX_BATCH=${MAX_BATCH_SIZE:-"4"}
MAX_INPUT=${MAX_INPUT_LEN:-"2048"}
MAX_SEQ=${MAX_SEQ_LEN:-"4096"}

echo "=============================================="
echo "TensorRT-LLM Pre-converted Checkpoint Deployment"
echo "=============================================="
echo "Checkpoint: $CHECKPOINT_MODEL"
echo "Tokenizer:  $TOKENIZER_MODEL"
echo "Max Batch:  $MAX_BATCH"
echo "Max Input:  $MAX_INPUT"
echo "Max Seq:    $MAX_SEQ"
echo "=============================================="

echo "--- STEP 1: Downloading Pre-converted Checkpoint ---"
# This checkpoint already has config.json + rank0.safetensors (ready for trtllm-build)
export CHECKPOINT_PATH=$(python3 -c "from huggingface_hub import snapshot_download; print(snapshot_download('${CHECKPOINT_MODEL}'))")
echo "Checkpoint downloaded to: $CHECKPOINT_PATH"
ls -la "$CHECKPOINT_PATH"

echo "--- STEP 2: Downloading Tokenizer from Base Model ---"
# Get tokenizer files from the original Mistral model
export TOKENIZER_PATH=$(python3 -c "from huggingface_hub import snapshot_download; print(snapshot_download('${TOKENIZER_MODEL}', allow_patterns=['*.json', '*.model', 'tokenizer*']))")
echo "Tokenizer downloaded to: $TOKENIZER_PATH"

echo "--- STEP 3: Starting TensorRT-LLM Server (T4 Optimized) ---"
echo "Server will be available at http://0.0.0.0:8000"
echo "OpenAI-compatible endpoints: /v1/completions, /v1/chat/completions"
echo ""
echo "Using custom serve_t4.py with context_fmha DISABLED for T4 compatibility"
echo "(T4 Turing architecture SM 75 doesn't support fused multi-head attention)"
echo ""

# Export environment variables for the Python script
export CHECKPOINT_PATH
export TOKENIZER_PATH
export HOST="0.0.0.0"
export PORT="8000"
export MAX_BATCH="$MAX_BATCH"
export MAX_SEQ="$MAX_SEQ"

# Run custom T4-optimized server
# Key difference from trtllm-serve: BuildConfig.plugin_config.context_fmha = False
python3 /serve_t4.py
