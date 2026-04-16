#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode"
DIST_DIR="$ROOT_DIR/.build/dist"
APP_NAME="JiraBar"
DMG_NAME="${APP_NAME}.dmg"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release/${APP_NAME}.app"
DMG_PATH="$ROOT_DIR/$DMG_NAME"

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo "▶ Building ${APP_NAME} (Release)…"
cd "$ROOT_DIR"
xcodebuild \
  -project JiraBar.xcodeproj \
  -scheme JiraBar \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

echo "✓ App: $APP_PATH"

# ── 2. Stage DMG contents ─────────────────────────────────────────────────────
echo "▶ Staging DMG contents…"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
cp -R "$APP_PATH" "$DIST_DIR/"
ln -s /Applications "$DIST_DIR/Applications"

# ── 3. Create DMG ─────────────────────────────────────────────────────────────
echo "▶ Creating DMG…"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DIST_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DIST_DIR"

echo ""
echo "✓ Done: $DMG_PATH"
echo ""
echo "⚠️  App is not code-signed. Users must right-click → Open to bypass Gatekeeper."
