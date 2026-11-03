#!/bin/bash
# VibeRadar — zero-config setup.
# On a new machine: git pull && ./scripts/setup.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "🎧 VibeRadar Setup"
echo "=================="
echo ""

# 1. Create local .env from the example when needed. Production/runtime
# secrets belong in Firebase Secret Manager, GitHub Actions secrets, and
# App Store Connect keys; this script must not decrypt repo-stored secrets.
if [ -f ".env" ]; then
  echo "✅ .env already exists"
else
  echo "⚠️  No .env found. Copying .env.example; fill local-only values as needed."
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
echo "📌 Secrets:"
echo "   Local .env is for developer overrides only."
echo "   Production Cloud Function secrets must be set in Firebase Secret Manager."
echo ""
