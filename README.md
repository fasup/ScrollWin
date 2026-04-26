# ScrollMouseWin

Menu bar app for macOS Apple Silicon that flips only mouse-wheel scrolling to behave like Windows.

## Features

- Reverse mouse-wheel scrolling up/down
- Leave trackpad scrolling alone
- Launch automatically at login
- Runs as a lightweight menu bar app

## Requirements

- macOS 13 or newer
- Accessibility permission enabled for the app

## Build

```bash
swift build
./scripts/build-app.sh
```

The app bundle will be created at `dist/ScrollMouseWin.app`.

## Run

Open `dist/ScrollMouseWin.app`.

On first launch, macOS will ask for Accessibility access. If it does not appear automatically, use the menu item `Open Accessibility Settings`.

## Notes

- The app flips only non-continuous scroll events, which is how standard mouse wheels are usually reported.
- `Launch at Login` writes a LaunchAgent plist to `~/Library/LaunchAgents/com.codex.scrollmousewin.plist`.
- If you move the app after enabling autostart, toggle `Launch at Login` off and on again so the saved path is refreshed.
