#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ScrollWin"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

# ─── Build both binaries ───────────────────────────────────────────────────────
swift build -c release --product ScrollMouseWin
swift build -c release --product ScrollMouseWinDaemon

# ─── Assemble app bundle ───────────────────────────────────────────────────────
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/ScrollMouseWin" "$MACOS_DIR/ScrollMouseWin"
cp "$BUILD_DIR/ScrollMouseWinDaemon" "$RESOURCES_DIR/scrollwin-daemon"
chmod +x "$RESOURCES_DIR/scrollwin-daemon"
echo "   Bundled daemon: $RESOURCES_DIR/scrollwin-daemon"
echo "   Daemon sig: $(codesign -dv "$RESOURCES_DIR/scrollwin-daemon" 2>&1 | grep ^Identifier || true)"

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
# Deep-sign the bundle: binds Info.plist and gives the main binary the bundle
# identifier com.codex.scrollmousewin (used for TCC / Accessibility lookups).
codesign --force --deep --sign - "$APP_DIR"

echo "✅ Built: $APP_DIR"
echo "   Main:   $(codesign -dv "$MACOS_DIR/ScrollMouseWin" 2>&1 | grep ^Identifier || true)"
