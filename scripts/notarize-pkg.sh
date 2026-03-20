#!/usr/bin/env bash
#
# LessonLens Package Notarization
# Notarizes and verifies a signed .pkg for Jamf deployment
#
# Usage:
#   bash scripts/notarize-pkg.sh
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# --- Configuration ---
PKG_PATH="$HOME/Desktop/LessonLens.pkg"
APP_PATH="$HOME/Desktop/LessonLens.app"
TEAM_ID="87DL7L9GU6"

# --- Validate ---
if [ ! -f "$PKG_PATH" ]; then
  echo -e "${RED}Error:${NC} $PKG_PATH not found"
  exit 1
fi

# --- Get credentials ---
read -r -p "$(echo -e "${BOLD}Apple ID:${NC} ")" APPLE_ID
read -r -s -p "$(echo -e "${BOLD}App-specific password:${NC} ")" APP_PASSWORD
echo ""

# --- Notarize ---
echo -e "${BOLD}Submitting .pkg for notarization...${NC}"
xcrun notarytool submit "$PKG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait

echo -e "${GREEN}✓${NC} Notarization complete"

# --- Staple ---
echo -e "${BOLD}Stapling notarization ticket...${NC}"
xcrun stapler staple "$PKG_PATH"
echo -e "${GREEN}✓${NC} Stapled"

# --- Verify ---
echo ""
echo -e "${BOLD}Verifying signatures...${NC}"

if [ -d "$APP_PATH" ]; then
  echo -e "\n${BOLD}.app verification:${NC}"
  spctl -a -vv "$APP_PATH"
fi

echo -e "\n${BOLD}.pkg verification:${NC}"
pkgutil --check-signature "$PKG_PATH"

echo ""
echo -e "${GREEN}✓${NC} Done. Upload ${BOLD}$PKG_PATH${NC} to Jamf Pro."
