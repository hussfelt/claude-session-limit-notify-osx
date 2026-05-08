#!/usr/bin/env bash
# Build a self-contained .app bundle for ClaudeSessionMonitor.
# Notifications via UNUserNotificationCenter require a code-signed bundle, so we
# ad-hoc sign at the end. That's enough for local use.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeSessionMonitor"
DISPLAY_NAME="Claude Session Monitor"
APP_DIR="$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)/$APP_NAME

if [ ! -x "$BIN_PATH" ]; then
  echo "Build failed: binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP_DIR"

echo
echo "Built: $(pwd)/$APP_DIR"
echo
echo "Run it once from Finder (double-click) so macOS prompts for notification permission."
echo "After the first launch you can move it to /Applications and add it to Login Items:"
echo "  System Settings → General → Login Items → '+' → select $DISPLAY_NAME"
