#!/bin/bash
# Build Game1 for macOS
# Usage: ./build.sh [scheme] [configuration]
#   scheme:      "Game1 macOS" (default) or "Game1 iOS"
#   configuration: "Debug" (default) or "Release"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

SCHEME="${1:-Game1 macOS}"
CONFIGURATION="${2:-Debug}"

echo "📦 Building Game1..."
echo "   Scheme:       $SCHEME"
echo "   Configuration: $CONFIGURATION"

xcodebuild -scheme "$SCHEME" \
           -configuration "$CONFIGURATION" \
           build 2>&1

echo ""
echo "✅ Build complete"
