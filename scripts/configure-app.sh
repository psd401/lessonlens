#!/usr/bin/env bash
#
# LessonLens App Configuration Script
# Updates the macOS app to point to your district's backend and branding
#
# Usage:
#   bash scripts/configure-app.sh            # Interactive configuration
#   bash scripts/configure-app.sh --dry-run  # Preview changes without applying
#

set -euo pipefail

# --- Configuration ---
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/LessonLens/LessonLens"
XCODEPROJ="$REPO_ROOT/LessonLens/LessonLens.xcodeproj/project.pbxproj"

# Default placeholder values (what we're replacing)
# If you've already configured these for your district, update them here
OLD_BUNDLE_ID="com.example.lessonlens"
OLD_BACKEND_URL="https://your-backend-url.run.app"
OLD_GOOGLE_CLIENT_ID="YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
OLD_ALLOWED_DOMAIN="example.org"
OLD_DISTRICT_NAME="Your School District"
OLD_GOOGLE_URL_SCHEME="com.googleusercontent.apps.YOUR_GOOGLE_CLIENT_ID"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Track changes
CHANGES_MADE=0

# --- Parse arguments ---
for arg in "$@"; do
  case $arg in
    --dry-run)
      DRY_RUN=true
      ;;
  esac
done

# --- Helper functions ---

print_header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

print_step() {
  echo -e "${GREEN}▸${NC} $1"
}

print_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

confirm() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would prompt: $1 [Y/n]"
    return 0
  fi
  read -r -p "$(echo -e "${BOLD}$1 [Y/n]:${NC} ")" response
  case "$response" in
    [nN][oO]|[nN])
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

prompt_value() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="${3:-}"

  if [ "$DRY_RUN" = true ]; then
    if [ -n "$default_value" ]; then
      echo -e "${YELLOW}[DRY RUN]${NC} Would prompt: $prompt_text (default: $default_value)"
      eval "$var_name='$default_value'"
    else
      echo -e "${YELLOW}[DRY RUN]${NC} Would prompt: $prompt_text"
      eval "$var_name='com.example.lessonlens'"
    fi
    return
  fi

  if [ -n "$default_value" ]; then
    read -r -p "$(echo -e "${BOLD}$prompt_text${NC} [$default_value]: ")" value
    eval "$var_name='${value:-$default_value}'"
  else
    while true; do
      read -r -p "$(echo -e "${BOLD}$prompt_text${NC}: ")" value
      if [ -n "$value" ]; then
        eval "$var_name='$value'"
        return
      fi
      print_error "This field is required."
    done
  fi
}

# Replace a string in a file, reporting what changed
replace_in_file() {
  local file="$1"
  local old="$2"
  local new="$3"
  local description="$4"

  if [ ! -f "$file" ]; then
    print_warn "File not found: $file"
    return
  fi

  # Check if the old string exists in the file
  if ! grep -q "$old" "$file" 2>/dev/null; then
    return
  fi

  local count
  count=$(grep -c "$old" "$file" 2>/dev/null || echo "0")
  local relative_path="${file#$REPO_ROOT/}"

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${NC} $relative_path: Would replace '$old' → '$new' ($count occurrence(s)) — $description"
  else
    # Use perl for reliable string replacement (handles special chars better than sed)
    perl -pi -e "s/\Q$old\E/$new/g" "$file"
    print_success "$relative_path: $description ($count replacement(s))"
  fi
  CHANGES_MADE=$((CHANGES_MADE + count))
}

# --- Main ---

print_header "LessonLens App Configuration"

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}Running in DRY RUN mode — no files will be modified.${NC}"
  echo ""
fi

# Verify we're in the right repo
if [ ! -d "$APP_DIR" ]; then
  print_error "App directory not found at $APP_DIR"
  print_error "Run this script from the LessonLens repository root."
  exit 1
fi

# --- Step 1: Gather configuration ---
print_header "Step 1: Configuration"

echo "Enter your district's configuration values."
echo ""

prompt_value CLOUD_RUN_URL "Cloud Run backend URL (e.g., https://lessonlens-api-xxxxx.us-west1.run.app)"
prompt_value NEW_GOOGLE_CLIENT_ID "Google OAuth Client ID"
prompt_value NEW_ALLOWED_DOMAIN "Email domain for login (e.g., mydistrict.org)"
prompt_value NEW_BUNDLE_ID "Bundle ID (e.g., com.mydistrict.lessonlens)"

echo ""
if confirm "Customize district branding (name and login text)?"; then
  CUSTOMIZE_BRANDING=true
  prompt_value NEW_DISTRICT_NAME "District name (displayed on login screen)" ""
  prompt_value NEW_DOMAIN_DISPLAY "Domain display text (e.g., @mydistrict.org)" "@${NEW_ALLOWED_DOMAIN}"
else
  CUSTOMIZE_BRANDING=false
fi

# Derive Google URL scheme from client ID
# Format: com.googleusercontent.apps.CLIENT_ID_PREFIX
NEW_GOOGLE_URL_SCHEME="com.googleusercontent.apps.$(echo "$NEW_GOOGLE_CLIENT_ID" | cut -d'.' -f1)"

echo ""
echo -e "${BOLD}Configuration summary:${NC}"
echo "  Backend URL:    $CLOUD_RUN_URL"
echo "  Client ID:      $NEW_GOOGLE_CLIENT_ID"
echo "  Domain:         $NEW_ALLOWED_DOMAIN"
echo "  Bundle ID:      $NEW_BUNDLE_ID"
echo "  URL Scheme:     $NEW_GOOGLE_URL_SCHEME"
if [ "$CUSTOMIZE_BRANDING" = true ]; then
  echo "  District name:  $NEW_DISTRICT_NAME"
  echo "  Domain display: $NEW_DOMAIN_DISPLAY"
fi
echo ""

if ! confirm "Apply these changes?"; then
  echo "Configuration cancelled."
  exit 0
fi

# --- Step 2: Update ServiceContainer.swift ---
print_header "Step 2: Updating Core Configuration"

SERVICE_CONTAINER="$APP_DIR/App/ServiceContainer.swift"

replace_in_file "$SERVICE_CONTAINER" \
  "$OLD_BACKEND_URL" "$CLOUD_RUN_URL" \
  "Backend URL"

replace_in_file "$SERVICE_CONTAINER" \
  "$OLD_GOOGLE_CLIENT_ID" "$NEW_GOOGLE_CLIENT_ID" \
  "Google Client ID"

replace_in_file "$SERVICE_CONTAINER" \
  "\"$OLD_ALLOWED_DOMAIN\"" "\"$NEW_ALLOWED_DOMAIN\"" \
  "Allowed domain"

# --- Step 3: Update bundle ID across all files ---
print_header "Step 3: Updating Bundle ID"

BUNDLE_ID_FILES=(
  "$APP_DIR/App/AppState.swift"
  "$APP_DIR/Core/Services/KeychainService.swift"
  "$APP_DIR/Core/Models/Recording.swift"
  "$APP_DIR/Features/Recording/RecordingService.swift"
  "$APP_DIR/Features/Recording/AudioImportService.swift"
  "$APP_DIR/Features/Recording/VideoImportService.swift"
  "$APP_DIR/Features/Recording/AudioExtractionService.swift"
  "$APP_DIR/Features/Settings/SettingsView.swift"
  "$APP_DIR/Resources/Info.plist"
  "$XCODEPROJ"
)

for file in "${BUNDLE_ID_FILES[@]}"; do
  replace_in_file "$file" \
    "$OLD_BUNDLE_ID" "$NEW_BUNDLE_ID" \
    "Bundle ID"
done

# --- Step 4: Update Google URL scheme in Info.plist ---
print_header "Step 4: Updating Google URL Scheme"

INFO_PLIST="$APP_DIR/Resources/Info.plist"

replace_in_file "$INFO_PLIST" \
  "$OLD_GOOGLE_URL_SCHEME" "$NEW_GOOGLE_URL_SCHEME" \
  "Google Sign-In URL scheme"

# Also check pbxproj in case URL scheme is referenced there
replace_in_file "$XCODEPROJ" \
  "$OLD_GOOGLE_URL_SCHEME" "$NEW_GOOGLE_URL_SCHEME" \
  "Google Sign-In URL scheme"

# --- Step 5: Update branding (optional) ---
if [ "$CUSTOMIZE_BRANDING" = true ]; then
  print_header "Step 5: Updating District Branding"

  LOGIN_VIEW="$APP_DIR/Features/Authentication/LoginView.swift"

  replace_in_file "$LOGIN_VIEW" \
    "$OLD_DISTRICT_NAME" "$NEW_DISTRICT_NAME" \
    "District name"

  replace_in_file "$LOGIN_VIEW" \
    "@$OLD_ALLOWED_DOMAIN" "$NEW_DOMAIN_DISPLAY" \
    "Domain display text"

  # Also update the domain check message in AppState.swift
  replace_in_file "$APP_DIR/App/AppState.swift" \
    "@$OLD_ALLOWED_DOMAIN" "@$NEW_ALLOWED_DOMAIN" \
    "Auth error domain message"
fi

# --- Step 6: Validation ---
print_header "Step 6: Validation"

echo "Checking for remaining old references..."
echo ""

VALIDATION_PASSED=true

# Check for old bundle ID
OLD_REFS=$(grep -r "$OLD_BUNDLE_ID" "$APP_DIR" "$XCODEPROJ" 2>/dev/null || true)
if [ -n "$OLD_REFS" ]; then
  print_warn "Old bundle ID ($OLD_BUNDLE_ID) still found in:"
  echo "$OLD_REFS" | while IFS= read -r line; do
    echo "    $line"
  done
  VALIDATION_PASSED=false
else
  print_success "No old bundle ID references found"
fi

# Check for old backend URL
OLD_URL_REFS=$(grep -r "$OLD_BACKEND_URL" "$APP_DIR" 2>/dev/null || true)
if [ -n "$OLD_URL_REFS" ]; then
  print_warn "Old backend URL still found in:"
  echo "$OLD_URL_REFS" | while IFS= read -r line; do
    echo "    $line"
  done
  VALIDATION_PASSED=false
else
  print_success "No old backend URL references found"
fi

# Check for old Google Client ID
OLD_CLIENT_REFS=$(grep -r "$OLD_GOOGLE_CLIENT_ID" "$APP_DIR" "$XCODEPROJ" 2>/dev/null || true)
if [ -n "$OLD_CLIENT_REFS" ]; then
  print_warn "Old Google Client ID still found in:"
  echo "$OLD_CLIENT_REFS" | while IFS= read -r line; do
    echo "    $line"
  done
  VALIDATION_PASSED=false
else
  print_success "No old Google Client ID references found"
fi

# Check new values are present
echo ""
echo "Verifying new values are present..."

if grep -q "$NEW_BUNDLE_ID" "$XCODEPROJ" 2>/dev/null; then
  print_success "New bundle ID found in project.pbxproj"
else
  print_warn "New bundle ID NOT found in project.pbxproj"
  VALIDATION_PASSED=false
fi

if grep -q "$CLOUD_RUN_URL" "$SERVICE_CONTAINER" 2>/dev/null; then
  print_success "New backend URL found in ServiceContainer.swift"
else
  print_warn "New backend URL NOT found in ServiceContainer.swift"
  VALIDATION_PASSED=false
fi

echo ""
if [ "$VALIDATION_PASSED" = true ]; then
  print_success "All validations passed!"
else
  print_warn "Some validations had warnings — review the output above."
fi

# --- Summary ---
print_header "Configuration Complete"

echo -e "${BOLD}Changes made:${NC} $CHANGES_MADE replacement(s) across all files"
echo ""
echo -e "${BOLD}Remaining manual steps:${NC}"
echo ""
echo "  1. Open LessonLens/LessonLens.xcodeproj in Xcode"
echo "  2. Select the LessonLens target → Signing & Capabilities"
echo "  3. Select your Apple Developer team"
echo "  4. Verify the bundle ID is: $NEW_BUNDLE_ID"
echo "  5. Build and test (Product → Build)"
echo "  6. Archive for distribution (Product → Archive)"
echo "  7. Notarize and export (Distribute App → Developer ID → Upload)"
echo "  8. Package as .pkg and deploy via your MDM"
echo ""
echo "  See docs/DEPLOYMENT.md Phase 4 for detailed instructions."
echo ""
