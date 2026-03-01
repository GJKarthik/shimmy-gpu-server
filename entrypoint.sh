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

echo "--- STEP 3: Starting TensorRT-LLM Server ---"
echo "Server will be available at http://0.0.0.0:8000"
echo "OpenAI-compatible endpoints: /v1/completions, /v1/chat/completions"
echo ""
echo "trtllm-serve will automatically build the TensorRT engine from the checkpoint"
echo "and start serving. This may take a few minutes on first run..."
echo ""

# TensorRT-LLM serve command (validated against v0.17.0/v0.18.0 serve.py):
# 
# The trtllm-serve command handles both engine building AND serving in one step.
# It accepts: model name | HF checkpoint path | safetensors directory
# It does NOT accept pre-built TensorRT engine directories.
#
# Arguments:
# - MODEL: positional argument - checkpoint path (not engine directory!)
# - --tokenizer: Path to tokenizer 
# - --host: Server hostname
# - --port: Server port
# - --max_batch_size, --max_seq_len, etc: Build configuration options
#
trtllm-serve "$CHECKPOINT_PATH" \
    --tokenizer "$TOKENIZER_PATH" \
    --host 0.0.0.0 \
    --port 8000 \
    --max_batch_size "$MAX_BATCH" \
    --max_seq_len "$MAX_SEQ"
