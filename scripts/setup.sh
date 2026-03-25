#!/bin/bash
# VibeRadar — one-command setup for any machine
# Usage: ./scripts/setup.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"

echo "🎧 VibeRadar Setup"
echo "=================="
echo ""

# 1. Create .env if missing
if [ -f "$ENV_FILE" ]; then
  echo "✅ .env already exists"
else
  echo "Creating .env from template..."
  cp "$ROOT/.env.example" "$ENV_FILE"

  # Prompt for OpenAI key
  echo ""
  read -rp "Enter your OpenAI API key (or press Enter to skip): " OPENAI_KEY
  if [ -n "$OPENAI_KEY" ]; then
    sed -i '' "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=$OPENAI_KEY|" "$ENV_FILE"
    echo "✅ OpenAI key saved to .env"
  else
    echo "⚠️  No OpenAI key — AI Copilot will run in simulation mode"
  fi
fi

# 2. Flutter pub get
echo ""
echo "Installing Flutter dependencies..."
cd "$ROOT"
flutter pub get

# 3. Cloud Functions dependencies
if [ -d "$ROOT/functions" ]; then
  echo ""
  echo "Installing Cloud Functions dependencies..."
  cd "$ROOT/functions"
  npm install
fi

echo ""
echo "✅ Setup complete! Run the app with:"
echo "   flutter run -d macos"
echo ""
echo "📌 API keys status:"
echo "   • OpenAI (AI Copilot): $(grep -q 'OPENAI_API_KEY=sk-' "$ENV_FILE" 2>/dev/null && echo '✅ Set' || echo '⚠️  Not set — add to .env')"
echo "   • Firebase:            ✅ Hardcoded in firebase_options.dart"
echo "   • Spotify/YouTube/Apple Music: ✅ In Firebase Secret Manager (cloud-side)"
echo ""
