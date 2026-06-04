#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

run() {
  echo ""
  echo "==> $*"
  "$@"
}

run flutter pub get
run flutter analyze
run flutter test
run npm --prefix functions run build
run flutter build web --release --no-wasm-dry-run

if [[ "${QA_BUILD_MACOS:-1}" == "1" ]]; then
  run flutter build macos --debug
else
  echo ""
  echo "==> Skipping macOS build because QA_BUILD_MACOS=0"
fi

if [[ "${QA_BUILD_ANDROID:-0}" == "1" ]]; then
  run flutter build apk --debug
else
  echo ""
  echo "==> Skipping Android APK build. Set QA_BUILD_ANDROID=1 to run it."
fi

if [[ "${QA_BUILD_IOS_SIM:-0}" == "1" ]]; then
  run flutter build ios --simulator --debug
else
  echo ""
  echo "==> Skipping iOS simulator build. Set QA_BUILD_IOS_SIM=1 to run it."
fi

echo ""
echo "Local QA smoke checks passed."
