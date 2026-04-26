#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ScrollWin"
APP_DIR="$DIST_DIR/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/release"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-macOS.zip"

cd "$ROOT_DIR"

./scripts/build-app.sh

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "✅ Packaged: $ZIP_PATH"
