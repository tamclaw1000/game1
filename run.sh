#!/bin/bash
# Build and run Game1 for macOS
# Usage: ./run.sh [configuration]
#   configuration: "Debug" (default) or "Release"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="${1:-Debug}"

# Build first
./build.sh "Game1 macOS" "$CONFIGURATION"

# Find the built app
DERIVED_DATA="$ROOT_DIR/Game1.xcodeproj/derived-data"
if [ ! -d "$DERIVED_DATA" ]; then
  DERIVED_DATA=$(xcodebuild -scheme "Game1 macOS" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null \
    | grep "BUILT_PRODUCTS_DIR" \
    | head -1 \
    | awk '{print $NF}')
fi

APP_PATH="$DERIVED_DATA/Game1.app"
if [ ! -d "$APP_PATH" ]; then
  echo "❌ Could not find built app at: $APP_PATH"
  exit 1
fi

echo "🚀 Launching Game1..."
open "$APP_PATH"
echo "✅ App launched"
