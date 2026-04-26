#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ScrollWin"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
MAIN_BINARY="$MACOS_DIR/ScrollMouseWin"
DAEMON_BINARY="$RESOURCES_DIR/scrollwin-daemon"

cd "$ROOT_DIR"

# ─── Build both binaries ───────────────────────────────────────────────────────
swift build -c release --product ScrollMouseWin
swift build -c release --product ScrollMouseWinDaemon

# ─── Assemble app bundle ───────────────────────────────────────────────────────
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/ScrollMouseWin" "$MAIN_BINARY"
cp "$BUILD_DIR/ScrollMouseWinDaemon" "$DAEMON_BINARY"
chmod +x "$DAEMON_BINARY"
echo "   Bundled daemon: $DAEMON_BINARY"
echo "   Daemon sig: $(codesign -dv "$DAEMON_BINARY" 2>&1 | grep ^Identifier || true)"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>ScrollWin</string>
    <key>CFBundleExecutable</key>
    <string>ScrollMouseWin</string>
    <key>CFBundleIdentifier</key>
    <string>com.codex.scrollmousewin</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ScrollWin</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>ScrollWin needs Accessibility access to reverse the mouse scroll wheel direction.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Used to open Accessibility settings.</string>
</dict>
</plist>
PLIST

# ─── Code-sign app bundle ─────────────────────────────────────────────────────
# For distribution, pass:
#   SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# This enables hardened runtime and secure timestamps for notarization.
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$DAEMON_BINARY"
  codesign --force --sign - "$MAIN_BINARY"
  codesign --force --sign - "$APP_DIR"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$DAEMON_BINARY"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$MAIN_BINARY"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi

echo "✅ Built: $APP_DIR"
echo "   Main:   $(codesign -dv "$MAIN_BINARY" 2>&1 | grep ^Identifier || true)"
