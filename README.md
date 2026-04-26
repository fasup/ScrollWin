# ScrollWin

ScrollWin is a lightweight macOS menu bar app that reverses only your mouse wheel scroll direction, so an external mouse behaves more like Windows while your trackpad keeps its normal macOS scrolling.

It is designed for people who want:

- Natural scrolling on trackpad
- Opposite scrolling on a physical mouse
- A small menu bar utility with no Dock icon
- Quick access to Accessibility settings and launch-at-login

## Features

- Reverse mouse-wheel scrolling without changing trackpad scrolling
- Runs as a lightweight menu bar app
- Launch at login support
- Accessibility shortcut built into the menu
- Menu bar icon style picker

## Requirements

- macOS 13 or newer
- Apple Silicon Mac
- Accessibility permission for `scrollwin-daemon`

## Installation

### Option 1: Build from source

```bash
swift build
./scripts/build-app.sh
```

This creates the app at `dist/ScrollWin.app`.

### Option 2: Build a distributable zip

```bash
./scripts/package-release.sh
```

This creates a ready-to-share archive at `release/ScrollWin-macOS.zip`.

### Option 2: Run the built app

Open:

```bash
dist/ScrollWin.app
```

When the app starts for the first time:

1. Click the menu bar icon.
2. Choose `Open Accessibility Settings` if macOS does not open it automatically.
3. In `System Settings > Privacy & Security > Accessibility`, enable `scrollwin-daemon`.
4. If needed, quit and reopen the app once after granting permission.

## Usage

- Use `Reverse Mouse Scroll` to turn mouse inversion on or off.
- Use `Launch at Login` to start ScrollWin automatically.
- Use `Icon Style` to choose the menu bar icon you prefer.

## How It Works

ScrollWin installs a small background daemon at:

```bash
~/bin/scrollwin-daemon
```

That daemon listens for mouse wheel scroll events and inverts them before they reach apps. Trackpad-style scrolling is left alone as much as possible.

The distributable `.app` bundle already includes the daemon inside it. On first launch, ScrollWin copies that daemon into your user account automatically, so the same app bundle can be moved to another Mac without rebuilding.

## Notes

- `Launch at Login` writes a LaunchAgent plist to `~/Library/LaunchAgents/com.codex.scrollmousewin.plist`.
- Mouse Accessibility permission is granted to `scrollwin-daemon`, not just the app bundle.
- If you move the app after enabling launch at login, toggle `Launch at Login` off and on again to refresh the saved path.
