#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode"

cd "$ROOT_DIR"
xcodebuild \
  -project JiraBar.xcodeproj \
  -scheme JiraBar \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

echo "Built app:"
echo "$DERIVED_DATA_DIR/Build/Products/Release/JiraBar.app"
