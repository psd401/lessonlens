#!/usr/bin/env bash
#
# Verify a built LessonLens.app carries district configuration from
# LessonLens/Config/Local.xcconfig before it is signed or packaged.
#
# Usage:
#   bash scripts/check-app-config.sh /path/to/LessonLens.app
#
# Exits non-zero if any LL_* value is empty or the bundle ID is the placeholder.
# Apps without the LL* Info.plist keys (other apps, or builds made before the
# xcconfig change) are skipped.
#

set -euo pipefail

APP_PATH="${1:?Usage: bash scripts/check-app-config.sh /path/to/LessonLens.app}"
PLIST="$APP_PATH/Contents/Info.plist"

if [ ! -f "$PLIST" ]; then
  echo "Error: $PLIST not found" >&2
  exit 1
fi

read_key() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true
}

if ! /usr/libexec/PlistBuddy -c "Print :LLBackendHost" "$PLIST" >/dev/null 2>&1; then
  echo "Skipping LessonLens config check: $PLIST has no LLBackendHost key."
  exit 0
fi

MISSING=()
for key in LLBackendHost LLGoogleClientIDPrefix LLAllowedDomain; do
  [ -n "$(read_key "$key")" ] || MISSING+=("$key")
done
if [ "$(read_key CFBundleIdentifier)" = "com.example.lessonlens" ]; then
  MISSING+=("CFBundleIdentifier (still com.example.lessonlens)")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Error: $APP_PATH was built without district configuration:" >&2
  for item in "${MISSING[@]}"; do
    echo "  - $item" >&2
  done
  echo "Create LessonLens/Config/Local.xcconfig (bash scripts/configure-app.sh) and rebuild." >&2
  exit 1
fi

echo "LessonLens config check passed ($(read_key LLBackendHost), @$(read_key LLAllowedDomain))."
