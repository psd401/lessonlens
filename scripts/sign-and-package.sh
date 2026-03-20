#!/usr/bin/env bash
#
# PSD macOS App Signing & Packaging
# Full pipeline: sign → notarize → staple → package → notarize pkg → verify
#
# Usage:
#   bash sign-and-package.sh /path/to/MyApp.app
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- PSD constants ---
TEAM_ID="87DL7L9GU6"
APP_SIGNING_IDENTITY="Developer ID Application: Peninsula School District ($TEAM_ID)"
PKG_SIGNING_IDENTITY="Developer ID Installer: Peninsula School District ($TEAM_ID)"

# --- Validate input ---
APP_PATH="${1:-}"

if [ -z "$APP_PATH" ]; then
  echo -e "${RED}Usage:${NC} bash sign-and-package.sh /path/to/MyApp.app"
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo -e "${RED}Error:${NC} $APP_PATH not found"
  exit 1
fi

# Derive app name (e.g., "LessonLens" from "LessonLens.app")
APP_BASENAME=$(basename "$APP_PATH")
APP_NAME="${APP_BASENAME%.app}"
APP_NAME_LOWER=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# --- Gather inputs ---
echo -e "${BOLD}PSD macOS App Signing & Packaging${NC}"
echo ""

read -r -p "$(echo -e "${BOLD}Apple ID:${NC} ")" APPLE_ID
read -r -s -p "$(echo -e "${BOLD}App-specific password:${NC} ")" APP_PASSWORD
echo ""
read -r -p "$(echo -e "${BOLD}Version number (e.g., 1.0):${NC} ")" VERSION
read -r -p "$(echo -e "${BOLD}Bundle identifier${NC} [net.psd401.${APP_NAME_LOWER}]: ")" PKG_ID
PKG_ID="${PKG_ID:-net.psd401.${APP_NAME_LOWER}}"

OUTPUT_PKG="$HOME/Desktop/${APP_NAME}.pkg"

echo ""
echo -e "${BOLD}Configuration:${NC}"
echo "  App:        $APP_PATH"
echo "  Apple ID:   $APPLE_ID"
echo "  Version:    $VERSION"
echo "  Identifier: $PKG_ID"
echo "  Output:     $OUTPUT_PKG"
echo ""
read -r -p "$(echo -e "${BOLD}Proceed? [Y/n]:${NC} ")" CONFIRM
case "$CONFIRM" in
  [nN][oO]|[nN]) echo "Cancelled."; exit 0 ;;
esac

# --- Step 1: Remove quarantine ---
echo ""
echo -e "${BOLD}Step 1: Removing quarantine${NC}"
xattr -cr "$APP_PATH"
echo -e "${GREEN}✓${NC} Quarantine removed"

# --- Step 2: Sign with Developer ID ---
echo -e "${BOLD}Step 2: Signing .app${NC}"
codesign --deep --force --options runtime \
  --sign "$APP_SIGNING_IDENTITY" "$APP_PATH"
echo -e "${GREEN}✓${NC} Signed"

# --- Step 3: Zip for notarization ---
echo -e "${BOLD}Step 3: Zipping for notarization${NC}"
ZIP_PATH="/tmp/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo -e "${GREEN}✓${NC} Zipped to $ZIP_PATH"

# --- Step 4: Notarize .app ---
echo -e "${BOLD}Step 4: Notarizing .app (this may take a few minutes)${NC}"
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait
echo -e "${GREEN}✓${NC} Notarization complete"

# --- Step 5: Staple .app ---
echo -e "${BOLD}Step 5: Stapling .app${NC}"
xcrun stapler staple "$APP_PATH"
echo -e "${GREEN}✓${NC} Stapled"

# --- Step 6: Build .pkg ---
echo -e "${BOLD}Step 6: Building .pkg${NC}"
PAYLOAD_DIR=$(mktemp -d)
mkdir -p "$PAYLOAD_DIR/Applications"
cp -R "$APP_PATH" "$PAYLOAD_DIR/Applications/"

pkgbuild \
  --root "$PAYLOAD_DIR" \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --install-location "/" \
  --sign "$PKG_SIGNING_IDENTITY" \
  "$OUTPUT_PKG"

rm -rf "$PAYLOAD_DIR"
echo -e "${GREEN}✓${NC} Package built: $OUTPUT_PKG"

# --- Step 7: Notarize .pkg ---
echo -e "${BOLD}Step 7: Notarizing .pkg${NC}"
xcrun notarytool submit "$OUTPUT_PKG" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait

xcrun stapler staple "$OUTPUT_PKG"
echo -e "${GREEN}✓${NC} Package notarized and stapled"

# --- Step 8: Verify ---
echo ""
echo -e "${BOLD}Step 8: Verifying signatures${NC}"
echo -e "\n${BOLD}.app:${NC}"
spctl -a -vv "$APP_PATH"
echo -e "\n${BOLD}.pkg:${NC}"
pkgutil --check-signature "$OUTPUT_PKG"

# --- Step 9: Clean up quarantine ---
echo -e "\n${BOLD}Step 9: Final quarantine cleanup${NC}"
xattr -r -d com.apple.quarantine "$APP_PATH" 2>/dev/null || true
echo -e "${GREEN}✓${NC} Clean"

# --- Cleanup temp files ---
rm -f "$ZIP_PATH"

# --- Done ---
echo ""
echo -e "${GREEN}✓${NC} Done. Package ready at: ${BOLD}$OUTPUT_PKG${NC}"
echo "  Upload to Jamf Pro for Self Service distribution."
