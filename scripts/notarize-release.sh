#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ScrollWin"
RELEASE_DIR="$ROOT_DIR/release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-macOS.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

cd "$ROOT_DIR"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "ERROR: Set SIGNING_IDENTITY to your Developer ID Application certificate name."
  echo 'Example: SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"'
  exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "ERROR: Set NOTARY_PROFILE to a notarytool keychain profile name."
  echo 'Create one with: xcrun notarytool store-credentials "ScrollWinNotary" --apple-id ... --team-id ... --password ...'
  exit 1
fi

SIGNING_IDENTITY="$SIGNING_IDENTITY" ./scripts/package-release.sh

echo "🔎 Verifying code signature before notarization..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR" || true

echo "☁️ Submitting $ZIP_PATH for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$APP_DIR"

echo "🧪 Verifying stapled app..."
xcrun stapler validate "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

echo "✅ Notarized app ready: $APP_DIR"
echo "✅ Notarized archive: $ZIP_PATH"
