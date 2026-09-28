#!/usr/bin/env bash
#
# LessonLens App Configuration Script
# Writes LessonLens/Config/Local.xcconfig (git-ignored) with your district's
# backend, Google OAuth client, domain, bundle ID, and Apple team, and
# optionally updates the district name on the login screen.
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
LOCAL_XCCONFIG="$REPO_ROOT/LessonLens/Config/Local.xcconfig"

# District name shipped in the login screen (what the branding step replaces)
OLD_DISTRICT_NAME="Peninsula School District"



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
prompt_value NEW_TEAM_ID "Apple Developer Team ID (10 characters)"

echo ""
if confirm "Customize district name on the login screen?"; then
  CUSTOMIZE_BRANDING=true
  prompt_value NEW_DISTRICT_NAME "District name (displayed on login screen)" ""
else
  CUSTOMIZE_BRANDING=false
fi

# xcconfig treats "//" as a comment, so store the backend host without the scheme
NEW_BACKEND_HOST="${CLOUD_RUN_URL#https://}"
NEW_BACKEND_HOST="${NEW_BACKEND_HOST#http://}"
NEW_BACKEND_HOST="${NEW_BACKEND_HOST%%/*}"

# The app appends ".apps.googleusercontent.com" and derives the OAuth URL scheme from this prefix
NEW_GOOGLE_CLIENT_ID_PREFIX="${NEW_GOOGLE_CLIENT_ID%.apps.googleusercontent.com}"

echo ""
echo -e "${BOLD}Configuration summary:${NC}"
echo "  Backend host:     $NEW_BACKEND_HOST"
echo "  Client ID prefix: $NEW_GOOGLE_CLIENT_ID_PREFIX"
echo "  Domain:           $NEW_ALLOWED_DOMAIN"
echo "  Bundle ID:        $NEW_BUNDLE_ID"
echo "  Team ID:          $NEW_TEAM_ID"
if [ "$CUSTOMIZE_BRANDING" = true ]; then
  echo "  District name:    $NEW_DISTRICT_NAME"
fi
echo ""

if ! confirm "Apply these changes?"; then
  echo "Configuration cancelled."
  exit 0
fi

# --- Step 2: Write Local.xcconfig ---
print_header "Step 2: Writing Local.xcconfig"

LOCAL_CONTENT="// District build settings for LessonLens. Git-ignored; do not commit.
// Generated by scripts/configure-app.sh. See Local.example.xcconfig.

LL_BUNDLE_ID = $NEW_BUNDLE_ID
LL_DEVELOPMENT_TEAM = $NEW_TEAM_ID
LL_BACKEND_HOST = $NEW_BACKEND_HOST
LL_GOOGLE_CLIENT_ID_PREFIX = $NEW_GOOGLE_CLIENT_ID_PREFIX
LL_ALLOWED_DOMAIN = $NEW_ALLOWED_DOMAIN"

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}[DRY RUN]${NC} Would write ${LOCAL_XCCONFIG#$REPO_ROOT/}:"
  echo "$LOCAL_CONTENT" | sed 's/^/    /'
else
  if [ -f "$LOCAL_XCCONFIG" ] && ! confirm "Local.xcconfig already exists. Overwrite?"; then
    echo "Configuration cancelled."
    exit 0
  fi
  echo "$LOCAL_CONTENT" > "$LOCAL_XCCONFIG"
  print_success "Wrote ${LOCAL_XCCONFIG#$REPO_ROOT/}"
fi

# --- Step 3: Update branding (optional) ---
if [ "$CUSTOMIZE_BRANDING" = true ]; then
  print_header "Step 3: Updating District Name"

  replace_in_file "$APP_DIR/Features/Authentication/LoginView.swift" \
    "$OLD_DISTRICT_NAME" "$NEW_DISTRICT_NAME" \
    "District name"
fi

# --- Summary ---
print_header "Configuration Complete"

echo -e "${BOLD}Remaining manual steps:${NC}"
echo ""
echo "  1. Open LessonLens/LessonLens.xcodeproj in Xcode"
echo "  2. Build and test (Product → Build); the bundle ID and team come from Local.xcconfig"
echo "  3. Archive for distribution (Product → Archive)"
echo "  4. Notarize and export (Distribute App → Developer ID → Upload)"
echo "  5. Package as .pkg and deploy via your MDM"
echo ""
echo "  Keep Local.xcconfig somewhere safe; release builds need it."
echo "  See docs/DEPLOYMENT.md Phase 4 for detailed instructions."
echo ""
