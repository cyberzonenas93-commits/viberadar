#!/bin/bash
# Load .env file and build with dart-define
set -a
source .env
set +a

flutter build macos \
  --dart-define=OPENAI_API_KEY="$OPENAI_API_KEY" \
  --dart-define=OPENAI_MODEL="${OPENAI_MODEL:-gpt-4.1}"

echo "Build complete. API key injected via --dart-define."
