#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/ScrollWin.app"

cd "$ROOT_DIR"

if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: App bundle not found at $APP_DIR"
  echo "Run ./scripts/build-app.sh or ./scripts/notarize-release.sh first."
  exit 1
fi

echo "🔎 codesign verification"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "🔎 Gatekeeper assessment"
spctl --assess --type execute --verbose=4 "$APP_DIR"

echo "🔎 Stapler validation"
xcrun stapler validate "$APP_DIR"

echo "✅ Verification complete"
