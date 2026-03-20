#!/usr/bin/env bash
#
# LessonLens Installer Package Builder
# Packages a signed/notarized .app into a signed .pkg for Jamf deployment
#
# Usage:
#   bash scripts/package.sh /path/to/LessonLens.app
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# --- Configuration ---
APP_PATH="${1:-}"
PKG_IDENTIFIER="net.psd401.lessonlens"
PKG_VERSION="1.0"
SIGNING_IDENTITY="Developer ID Installer: Peninsula School District (87DL7L9GU6)"
OUTPUT_DIR="$HOME/Desktop"
OUTPUT_PKG="$OUTPUT_DIR/LessonLens.pkg"
PAYLOAD_DIR=$(mktemp -d)

# --- Validate input ---
if [ -z "$APP_PATH" ]; then
  echo -e "${RED}Usage:${NC} bash scripts/package.sh /path/to/LessonLens.app"
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo -e "${RED}Error:${NC} $APP_PATH not found"
  exit 1
fi

# --- Build package ---
echo -e "${BOLD}Packaging LessonLens.app → LessonLens.pkg${NC}"

mkdir -p "$PAYLOAD_DIR/Applications"
cp -R "$APP_PATH" "$PAYLOAD_DIR/Applications/"
echo -e "${GREEN}✓${NC} Copied .app to payload"

pkgbuild \
  --root "$PAYLOAD_DIR" \
  --identifier "$PKG_IDENTIFIER" \
  --version "$PKG_VERSION" \
  --install-location "/" \
  --sign "$SIGNING_IDENTITY" \
  "$OUTPUT_PKG"
echo -e "${GREEN}✓${NC} Package built: $OUTPUT_PKG"

# --- Cleanup ---
rm -rf "$PAYLOAD_DIR"

# --- Verify ---
pkgutil --check-signature "$OUTPUT_PKG"

echo ""
echo -e "${GREEN}✓${NC} Done. Package ready at: ${BOLD}$OUTPUT_PKG${NC}"
echo "  Upload this to Jamf Pro for Self Service distribution."
