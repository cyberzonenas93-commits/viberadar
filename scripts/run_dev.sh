#!/bin/bash
set -a
source .env
set +a

flutter run -d macos \
  --dart-define=OPENAI_API_KEY="$OPENAI_API_KEY" \
  --dart-define=OPENAI_MODEL="${OPENAI_MODEL:-gpt-4.1}"
