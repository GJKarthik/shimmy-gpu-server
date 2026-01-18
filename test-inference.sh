#!/bin/bash
# Test script for Shimmy Inference Server
# This script tests the Gemma-2B-IT model inference capabilities

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SHIMMY_URL="${SHIMMY_URL:-http://localhost:8080}"

echo -e "${YELLOW}Testing Shimmy Inference Server with Gemma-2B-IT model${NC}"
echo "=========================================="
echo ""

# Test 1: Health check
echo -e "${YELLOW}Test 1: Health Check${NC}"
if curl -s -f "${SHIMMY_URL}/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
    exit 1
fi
echo ""

# Test 2: List available models
echo -e "${YELLOW}Test 2: List Available Models${NC}"
curl -s "${SHIMMY_URL}/v1/models" | jq '.' || echo "Failed to list models"
echo ""

# Test 3: Simple completion request
echo -e "${YELLOW}Test 3: Simple Completion Request${NC}"
echo "Prompt: 'Hello, how are you?'"
RESPONSE=$(curl -s -X POST "${SHIMMY_URL}/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-2b-it",
    "prompt": "Hello, how are you?",
    "max_tokens": 50,
    "temperature": 0.7
  }')

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Completion request successful${NC}"
    echo "Response:"
    echo "$RESPONSE" | jq '.choices[0].text' || echo "$RESPONSE"
else
    echo -e "${RED}✗ Completion request failed${NC}"
fi
echo ""

# Test 4: Chat completion request
echo -e "${YELLOW}Test 4: Chat Completion Request${NC}"
echo "Message: 'What is the capital of France?'"
CHAT_RESPONSE=$(curl -s -X POST "${SHIMMY_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-2b-it",
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ],
    "max_tokens": 100,
    "temperature": 0.5
  }')

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Chat completion request successful${NC}"
    echo "Response:"
    echo "$CHAT_RESPONSE" | jq '.choices[0].message.content' || echo "$CHAT_RESPONSE"
else
    echo -e "${RED}✗ Chat completion request failed${NC}"
fi
echo ""

# Test 5: Code generation request
echo -e "${YELLOW}Test 5: Code Generation Request${NC}"
echo "Prompt: 'Write a Python function to calculate factorial'"
CODE_RESPONSE=$(curl -s -X POST "${SHIMMY_URL}/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-2b-it",
    "prompt": "Write a Python function to calculate factorial of a number:",
    "max_tokens": 150,
    "temperature": 0.3
  }')

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Code generation request successful${NC}"
    echo "Generated code:"
    echo "$CODE_RESPONSE" | jq -r '.choices[0].text' || echo "$CODE_RESPONSE"
else
    echo -e "${RED}✗ Code generation request failed${NC}"
fi
echo ""

echo -e "${GREEN}=========================================="
echo "All tests completed!"
echo -e "==========================================${NC}"
