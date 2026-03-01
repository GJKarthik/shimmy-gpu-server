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

echo "--- STEP 3: Building TensorRT-LLM Engine (Optimized for T4) ---"
# Build engine directly from checkpoint (no conversion needed!)
# The checkpoint was created with TRT-LLM v0.18.0 convert_checkpoint.py
#
# T4 GPU Compatibility Notes (Turing architecture, SM 75):
# - context_fmha disable: T4 doesn't support fused multi-head attention kernel
# - gpt_attention_plugin float16: Use standard attention plugin instead
# - gemm_plugin float16: Use FP16 GEMM plugin
# - kv_cache_type paged: Use paged KV cache
# - remove_input_padding enable: Remove padding for better throughput
#
trtllm-build \
    --checkpoint_dir "$CHECKPOINT_PATH" \
    --output_dir "$TRT_ENGINE_DIR" \
    --max_batch_size "$MAX_BATCH" \
    --max_input_len "$MAX_INPUT" \
    --max_seq_len "$MAX_SEQ" \
    --kv_cache_type paged \
    --remove_input_padding enable \
    --gemm_plugin float16 \
    --gpt_attention_plugin float16 \
    --context_fmha disable

echo "Engine built successfully!"
ls -la "$TRT_ENGINE_DIR"

echo "--- STEP 4: Copying Tokenizer Files to Engine Directory ---"
# Copy tokenizer files so the server can decode tokens
cp "$TOKENIZER_PATH"/*.json "$TRT_ENGINE_DIR/" 2>/dev/null || true
cp "$TOKENIZER_PATH"/*.model "$TRT_ENGINE_DIR/" 2>/dev/null || true
cp "$TOKENIZER_PATH"/tokenizer* "$TRT_ENGINE_DIR/" 2>/dev/null || true
echo "Tokenizer files copied to engine directory"

echo "--- STEP 5: Starting TensorRT-LLM Server ---"
echo "Server will be available at http://0.0.0.0:8000"
echo "OpenAI-compatible endpoints: /v1/completions, /v1/chat/completions"

# Using trtllm-serve for OpenAI-compatible API
trtllm-serve "$TRT_ENGINE_DIR" \
    --tokenizer "$TOKENIZER_PATH" \
    --host 0.0.0.0 \
    --port 8000