#!/bin/bash
# VibeRadar — zero-config setup.
# On a new machine: git pull && ./scripts/setup.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "🎧 VibeRadar Setup"
echo "=================="
echo ""

# 1. Decrypt .env if not present
if [ ! -f ".env" ] && [ -f ".env.encrypted" ]; then
  echo "Decrypting .env..."
  openssl enc -aes-256-cbc -pbkdf2 -d -salt -in .env.encrypted -out .env -pass pass:VibeRadar2026
  echo "✅ .env decrypted"
elif [ -f ".env" ]; then
  echo "✅ .env already exists"
else
  echo "⚠️  No .env or .env.encrypted found. Copy .env.example and fill in your keys."
  cp .env.example .env
fi

# 2. Flutter dependencies
echo ""
echo "Installing Flutter dependencies..."
flutter pub get

# 3. Cloud Functions dependencies
if [ -d "functions" ]; then
  echo "Installing Cloud Functions dependencies..."
  cd functions && npm install && cd ..
fi

echo ""
echo "✅ Setup complete! Run the app:"
echo "   flutter run -d macos"
echo ""
echo "📌 API keys status:"
grep -q "OPENAI_API_KEY=sk-" .env 2>/dev/null && echo "   ✅ OpenAI (gpt-5.4)" || echo "   ❌ OpenAI — add to .env"
grep -q "SPOTIFY_CLIENT_ID=" .env 2>/dev/null && echo "   ✅ Spotify" || echo "   ❌ Spotify — add to .env"
echo "   ✅ Firebase (hardcoded)"
echo "   ✅ Billboard, Deezer (no auth)"
echo "   ✅ YouTube, Apple Music, SoundCloud (Firebase Secrets)"
echo ""
