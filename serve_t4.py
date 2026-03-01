#!/usr/bin/env python3
"""
TensorRT-LLM OpenAI-compatible Server for T4 GPU
Disables context_fmha which is not supported on Turing architecture (SM 75)
"""
import asyncio
import os
import sys

from transformers import AutoTokenizer
from tensorrt_llm.llmapi import LLM, BuildConfig, KvCacheConfig
from tensorrt_llm.llmapi.llm_utils import LlmArgs
from tensorrt_llm.serve import OpenAIServer


def main():
    # Get configuration from environment
    model = os.environ.get('CHECKPOINT_PATH')
    tokenizer_path = os.environ.get('TOKENIZER_PATH')
    host = os.environ.get('HOST', '0.0.0.0')
    port = int(os.environ.get('PORT', '8000'))
    max_batch_size = int(os.environ.get('MAX_BATCH', '4'))
    max_seq_len = int(os.environ.get('MAX_SEQ', '4096'))
    
    if not model:
        print("ERROR: CHECKPOINT_PATH environment variable not set")
        sys.exit(1)
    
    if not tokenizer_path:
        print("ERROR: TOKENIZER_PATH environment variable not set")
        sys.exit(1)
    
    print(f"Loading model from: {model}")
    print(f"Tokenizer path: {tokenizer_path}")
    print(f"Max batch size: {max_batch_size}")
    print(f"Max seq len: {max_seq_len}")
    print(f"Server will run at {host}:{port}")
    
    # Build configuration optimized for T4 GPU (Turing, SM 75)
    # CRITICAL: context_fmha must be disabled - T4 doesn't support fused MHA kernel
    build_config = BuildConfig(
        max_batch_size=max_batch_size,
        max_seq_len=max_seq_len,
        max_num_tokens=max_batch_size * max_seq_len // 2,  # Conservative estimate
        max_beam_width=1,
    )
    
    # Disable context_fmha for T4 compatibility
    # This is the key fix - T4 doesn't support the fused multi-head attention kernel
    build_config.plugin_config.context_fmha = False
    
    print(f"Build config - context_fmha: {build_config.plugin_config.context_fmha}")
    
    # KV cache configuration - use 90% of free GPU memory
    kv_cache_config = KvCacheConfig(free_gpu_memory_fraction=0.9)
    
    # Create LLM args
    llm_args = LlmArgs.from_kwargs(
        model=model,
        tokenizer=tokenizer_path,
        tensor_parallel_size=1,
        pipeline_parallel_size=1,
        trust_remote_code=False,
        build_config=build_config,
        kv_cache_config=kv_cache_config,
        backend=None  # Use cpp backend
    )
    
    print("Initializing LLM (this will build the TensorRT engine)...")
    llm = LLM(**llm_args.to_dict())
    print("LLM initialized successfully!")
    
    # Load tokenizer for the server
    print(f"Loading tokenizer from: {tokenizer_path}")
    hf_tokenizer = AutoTokenizer.from_pretrained(tokenizer_path)
    
    # Create and run OpenAI-compatible server
    print(f"Starting OpenAI-compatible server on {host}:{port}")
    server = OpenAIServer(llm=llm, model=model, hf_tokenizer=hf_tokenizer)
    
    asyncio.run(server(host, port))


if __name__ == "__main__":
    main()