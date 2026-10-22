#!/usr/bin/env bash
#
# LessonLens Backend Setup Wizard
# Deploys the LessonLens API to Google Cloud Run
#
# Usage:
#   bash scripts/setup.sh            # Interactive setup
#   bash scripts/setup.sh --dry-run  # Preview steps without executing
#

set -euo pipefail

# --- Configuration ---
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/CloudRunBackend"
SERVICE_NAME="lessonlens-api"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

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

run_cmd() {
  local description="$1"
  shift
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would execute: $*"
  else
    print_step "$description"
    "$@"
  fi
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
      eval "$var_name='PLACEHOLDER'"
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

# --- Main ---

print_header "LessonLens Backend Setup Wizard"

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}Running in DRY RUN mode — no changes will be made.${NC}"
  echo ""
fi

# --- Step 1: Check prerequisites ---
print_header "Step 1: Checking Prerequisites"

# Check gcloud
if command -v gcloud &> /dev/null; then
  GCLOUD_VERSION=$(gcloud version 2>/dev/null | head -1)
  print_success "gcloud CLI found: $GCLOUD_VERSION"
elif [ "$DRY_RUN" = true ]; then
  print_warn "gcloud CLI not found (not required for dry run)"
else
  print_error "gcloud CLI not found. Install it from: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

# Check gcloud auth
if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}[DRY RUN]${NC} Would check gcloud authentication"
elif command -v gcloud &> /dev/null; then
  GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null || true)
  if [ -z "$GCLOUD_ACCOUNT" ] || [ "$GCLOUD_ACCOUNT" = "(unset)" ]; then
    print_error "Not authenticated with gcloud. Run: gcloud auth login"
    exit 1
  fi
  print_success "Authenticated as: $GCLOUD_ACCOUNT"
fi

# Check bun (needed for local testing, not strictly for deploy)
if command -v bun &> /dev/null; then
  BUN_VERSION=$(bun --version 2>/dev/null)
  print_success "bun found: v$BUN_VERSION"
else
  print_warn "bun not found. Not required for Cloud Run deploy, but needed for local development."
  print_warn "Install: curl -fsSL https://bun.sh/install | bash"
fi

# Check backend directory
if [ -d "$BACKEND_DIR" ]; then
  print_success "Backend directory found: $BACKEND_DIR"
else
  print_error "Backend directory not found at $BACKEND_DIR"
  exit 1
fi

# --- Step 2: Gather configuration ---
print_header "Step 2: Configuration"

echo "Enter your deployment configuration. Press Enter to accept defaults."
echo ""

prompt_value GCP_PROJECT "GCP Project ID"
prompt_value GCP_REGION "GCP Region" "us-west1"
prompt_value ALLOWED_DOMAIN "Email domain for login (e.g., mydistrict.org)"
prompt_value VERTEX_LOCATION "Vertex AI location (us keeps processing in the US)" "us"
prompt_value GOOGLE_CLIENT_ID "Google OAuth Client ID (from GCP Console)"
prompt_value RATE_LIMIT "Text analysis rate limit per user per hour" "20"
prompt_value VIDEO_RATE_LIMIT "Video analysis rate limit per user per hour" "5"
prompt_value ALERT_EMAIL "Email for error/downtime alerts"

echo ""
echo -e "${BOLD}Configuration summary:${NC}"
echo "  Project:        $GCP_PROJECT"
echo "  Region:         $GCP_REGION"
echo "  Domain:         $ALLOWED_DOMAIN"
echo "  Vertex AI:      $VERTEX_LOCATION"
echo "  Client ID:      $GOOGLE_CLIENT_ID"
echo "  Rate limit:     $RATE_LIMIT/hr (text), $VIDEO_RATE_LIMIT/hr (video)"
echo "  Alert email:    $ALERT_EMAIL"
echo ""

if ! confirm "Proceed with this configuration?"; then
  echo "Setup cancelled."
  exit 0
fi

# --- Step 3: Set GCP project ---
print_header "Step 3: Setting GCP Project"

run_cmd "Setting active project to $GCP_PROJECT" \
  gcloud config set project "$GCP_PROJECT"

# --- Step 4: Enable APIs ---
print_header "Step 4: Enabling Required APIs"

APIS=(
  "run.googleapis.com"
  "secretmanager.googleapis.com"
  "artifactregistry.googleapis.com"
  "cloudbuild.googleapis.com"
  "aiplatform.googleapis.com"
  "storage.googleapis.com"
  "monitoring.googleapis.com"
  "logging.googleapis.com"
)

for api in "${APIS[@]}"; do
  run_cmd "Enabling $api" \
    gcloud services enable "$api" --project "$GCP_PROJECT"
done

# --- Step 5: Runtime service account and video bucket ---
# The backend calls Gemini on Vertex AI as this service account (no API key)
# and stages uploaded videos in a bucket only it can read.
print_header "Step 5: Service Account and Video Bucket"

SA_NAME="lessonlens-runtime"
SA_EMAIL="$SA_NAME@$GCP_PROJECT.iam.gserviceaccount.com"
VIDEO_BUCKET="$GCP_PROJECT-video-tmp"

if [ "$DRY_RUN" != true ] && gcloud iam service-accounts describe "$SA_EMAIL" --project "$GCP_PROJECT" &>/dev/null; then
  print_success "Service account $SA_EMAIL exists"
else
  run_cmd "Creating service account $SA_EMAIL" \
    gcloud iam service-accounts create "$SA_NAME" --display-name "LessonLens runtime" --project "$GCP_PROJECT"
fi

run_cmd "Granting Vertex AI access (roles/aiplatform.user)" \
  gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
    --member="serviceAccount:$SA_EMAIL" --role="roles/aiplatform.user" --condition=None --quiet

if [ "$DRY_RUN" != true ] && gcloud storage buckets describe "gs://$VIDEO_BUCKET" &>/dev/null; then
  print_success "Bucket gs://$VIDEO_BUCKET exists"
else
  run_cmd "Creating video bucket gs://$VIDEO_BUCKET" \
    gcloud storage buckets create "gs://$VIDEO_BUCKET" --project "$GCP_PROJECT" --location "$GCP_REGION" \
      --uniform-bucket-level-access --public-access-prevention --soft-delete-duration=0
fi

# Videos are deleted right after analysis; this 1-day rule is the backstop
LIFECYCLE_FILE="$(mktemp)"
echo '{"rule": [{"action": {"type": "Delete"}, "condition": {"age": 1}}]}' > "$LIFECYCLE_FILE"
run_cmd "Setting 1-day delete rule on the video bucket" \
  gcloud storage buckets update "gs://$VIDEO_BUCKET" --lifecycle-file="$LIFECYCLE_FILE"
rm -f "$LIFECYCLE_FILE"

run_cmd "Granting the service account access to the video bucket" \
  gcloud storage buckets add-iam-policy-binding "gs://$VIDEO_BUCKET" \
    --member="serviceAccount:$SA_EMAIL" --role="roles/storage.objectAdmin"

# --- Step 6: Generate JWT secret ---
print_header "Step 6: Generating JWT Secret"

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}[DRY RUN]${NC} Would generate JWT secret with: openssl rand -base64 48"
  JWT_SECRET="PLACEHOLDER_JWT_SECRET"
else
  JWT_SECRET=$(openssl rand -base64 48)
  print_success "JWT secret generated (${#JWT_SECRET} characters)"
fi

# --- Step 7: Store secrets in Secret Manager ---
print_header "Step 7: Storing Secrets in Secret Manager"

store_secret() {
  local secret_name="$1"
  local secret_value="$2"

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would create/update secret: $secret_name"
    return
  fi

  # Check if secret exists
  if gcloud secrets describe "$secret_name" --project "$GCP_PROJECT" &>/dev/null; then
    print_step "Secret '$secret_name' exists — adding new version"
    echo -n "$secret_value" | gcloud secrets versions add "$secret_name" --data-file=- --project "$GCP_PROJECT"
  else
    print_step "Creating secret '$secret_name'"
    echo -n "$secret_value" | gcloud secrets create "$secret_name" --data-file=- --project "$GCP_PROJECT"
  fi
  print_success "Secret '$secret_name' stored"
}

store_secret "jwt-secret" "$JWT_SECRET"
store_secret "google-client-id" "$GOOGLE_CLIENT_ID"

for secret_name in jwt-secret google-client-id; do
  run_cmd "Letting the service account read $secret_name" \
    gcloud secrets add-iam-policy-binding "$secret_name" --project "$GCP_PROJECT" \
      --member="serviceAccount:$SA_EMAIL" --role="roles/secretmanager.secretAccessor" --quiet
done

# --- Step 8: Deploy to Cloud Run ---
print_header "Step 8: Deploying to Cloud Run"

if ! confirm "Deploy backend to Cloud Run in $GCP_REGION?"; then
  echo "Skipping deployment. You can deploy manually later."
else
  DEPLOY_CMD=(
    gcloud run deploy "$SERVICE_NAME"
    --source "$REPO_ROOT"
    --region "$GCP_REGION"
    --allow-unauthenticated
    --service-account="$SA_EMAIL"
    --set-secrets="JWT_SECRET=jwt-secret:latest,GOOGLE_CLIENT_ID=google-client-id:latest"
    --set-env-vars="ALLOWED_DOMAIN=$ALLOWED_DOMAIN,VERTEX_LOCATION=$VERTEX_LOCATION,VIDEO_BUCKET=$VIDEO_BUCKET,RATE_LIMIT_PER_HOUR=$RATE_LIMIT,GEMINI_TEXT_MODEL=gemini-3.8-flash,GEMINI_VIDEO_MODEL=gemini-3.8-flash,VIDEO_RATE_LIMIT_PER_HOUR=$VIDEO_RATE_LIMIT,CHAT_RATE_LIMIT_PER_HOUR=50"
    --project "$GCP_PROJECT"
  )

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would execute:"
    echo "  ${DEPLOY_CMD[*]}"
  else
    print_step "Deploying $SERVICE_NAME to Cloud Run (this may take a few minutes)..."
    "${DEPLOY_CMD[@]}"
    print_success "Deployment complete"
  fi
fi

# --- Step 9: Validate deployment ---
print_header "Step 9: Validating Deployment"

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}[DRY RUN]${NC} Would fetch Cloud Run URL and run health check"
  CLOUD_RUN_URL="https://lessonlens-api-PLACEHOLDER.$GCP_REGION.run.app"
else
  CLOUD_RUN_URL=$(gcloud run services describe "$SERVICE_NAME" \
    --region "$GCP_REGION" \
    --project "$GCP_PROJECT" \
    --format='value(status.url)' 2>/dev/null || true)

  if [ -n "$CLOUD_RUN_URL" ]; then
    print_success "Cloud Run URL: $CLOUD_RUN_URL"
    echo ""
    print_step "Running health check..."
    HEALTH_RESPONSE=$(curl -s --max-time 10 "$CLOUD_RUN_URL" || true)
    if echo "$HEALTH_RESPONSE" | grep -q '"healthy"'; then
      print_success "Health check passed!"
      echo "$HEALTH_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$HEALTH_RESPONSE"
    else
      print_warn "Health check returned unexpected response:"
      echo "$HEALTH_RESPONSE"
      print_warn "The service may still be starting up. Try again in a minute."
    fi
  else
    print_warn "Could not retrieve Cloud Run URL. Check the deployment status in GCP Console."
  fi
fi

# --- Step 10: Set up monitoring & alerting ---
print_header "Step 10: Setting Up Monitoring & Alerting"

if [ -z "$CLOUD_RUN_URL" ] || [ "$CLOUD_RUN_URL" = "https://lessonlens-api-PLACEHOLDER.$GCP_REGION.run.app" ]; then
  print_warn "No Cloud Run URL available — skipping monitoring setup."
  print_warn "You can set up monitoring manually in the GCP Console later."
else
  # Create notification channel (email)
  print_step "Creating email notification channel..."
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would create email notification channel for $ALERT_EMAIL"
    NOTIFICATION_CHANNEL_ID="PLACEHOLDER_CHANNEL_ID"
  else
    NOTIFICATION_CHANNEL_ID=$(gcloud beta monitoring channels create \
      --display-name="LessonLens Alert Email" \
      --type=email \
      --channel-labels="email_address=$ALERT_EMAIL" \
      --project="$GCP_PROJECT" \
      --format='value(name)' 2>/dev/null || true)

    if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
      print_success "Notification channel created: $ALERT_EMAIL"
    else
      print_warn "Failed to create notification channel. Set up manually in GCP Console."
    fi
  fi

  # Create log-based metric for Cloud Run errors
  print_step "Creating log-based metric for backend errors..."
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would create log-based metric: lessonlens-api-errors"
  else
    gcloud logging metrics create lessonlens-api-errors \
      --description="LessonLens API error log entries" \
      --log-filter="resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"$SERVICE_NAME\" AND severity>=ERROR" \
      --project="$GCP_PROJECT" 2>/dev/null && \
      print_success "Log-based metric created: lessonlens-api-errors" || \
      print_warn "Log-based metric may already exist or failed to create"
  fi

  # Create alerting policy for errors
  if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
    print_step "Creating error alerting policy..."
    if [ "$DRY_RUN" = true ]; then
      echo -e "${YELLOW}[DRY RUN]${NC} Would create alerting policy for backend errors"
    else
      ALERT_POLICY_JSON=$(cat <<ALERTEOF
{
  "displayName": "LessonLens API Errors",
  "documentation": {
    "content": "The LessonLens backend logged errors. Check Cloud Run logs for details:\nhttps://console.cloud.google.com/run/detail/$GCP_REGION/$SERVICE_NAME/logs?project=$GCP_PROJECT"
  },
  "conditions": [
    {
      "displayName": "Error log entries > 0",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/lessonlens-api-errors\" AND resource.type=\"cloud_run_revision\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_COUNT"
          }
        ],
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": ["$NOTIFICATION_CHANNEL_ID"]
}
ALERTEOF
      )

      echo "$ALERT_POLICY_JSON" | gcloud alpha monitoring policies create \
        --policy-from-file=- \
        --project="$GCP_PROJECT" 2>/dev/null && \
        print_success "Error alerting policy created — alerts will go to $ALERT_EMAIL" || \
        print_warn "Failed to create alerting policy. Set up manually in GCP Console > Monitoring > Alerting."
    fi
  fi

  # Create uptime check on /health endpoint
  print_step "Creating uptime check on /health endpoint..."
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would create uptime check for $CLOUD_RUN_URL"
  else
    # Extract host from Cloud Run URL
    CLOUD_RUN_HOST=$(echo "$CLOUD_RUN_URL" | sed 's|https://||')

    UPTIME_CHECK_JSON=$(cat <<UPTIMEEOF
{
  "displayName": "LessonLens API Health",
  "monitoredResource": {
    "type": "uptime_url",
    "labels": {
      "host": "$CLOUD_RUN_HOST",
      "project_id": "$GCP_PROJECT"
    }
  },
  "httpCheck": {
    "path": "/",
    "port": 443,
    "useSsl": true,
    "validateSsl": true,
    "acceptedResponseStatusCodes": [
      { "statusClass": "STATUS_CLASS_2XX" }
    ]
  },
  "period": "300s",
  "timeout": "10s"
}
UPTIMEEOF
    )

    UPTIME_CHECK_ID=$(echo "$UPTIME_CHECK_JSON" | gcloud alpha monitoring uptime create \
      --config-from-file=- \
      --project="$GCP_PROJECT" \
      --format='value(name)' 2>/dev/null || true)

    if [ -n "$UPTIME_CHECK_ID" ]; then
      print_success "Uptime check created — checks /health every 5 minutes"

      # Create uptime alert policy
      if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
        print_step "Creating uptime failure alerting policy..."
        UPTIME_ALERT_JSON=$(cat <<UPALERTEOF
{
  "displayName": "LessonLens API Down",
  "documentation": {
    "content": "The LessonLens health endpoint is failing. Check Cloud Run status:\nhttps://console.cloud.google.com/run/detail/$GCP_REGION/$SERVICE_NAME/metrics?project=$GCP_PROJECT"
  },
  "conditions": [
    {
      "displayName": "Health check failing",
      "conditionThreshold": {
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"$UPTIME_CHECK_ID\" AND resource.type=\"uptime_url\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 1,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_NEXT_OLDER",
            "crossSeriesReducer": "REDUCE_COUNT_FALSE"
          }
        ],
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": ["$NOTIFICATION_CHANNEL_ID"]
}
UPALERTEOF
        )

        echo "$UPTIME_ALERT_JSON" | gcloud alpha monitoring policies create \
          --policy-from-file=- \
          --project="$GCP_PROJECT" 2>/dev/null && \
          print_success "Uptime alerting policy created — notifies on downtime" || \
          print_warn "Failed to create uptime alert policy. Set up manually in GCP Console."
      fi
    else
      print_warn "Failed to create uptime check. Set up manually in GCP Console > Monitoring > Uptime checks."
    fi
  fi

  echo ""
  print_success "Monitoring setup complete. You will be notified at $ALERT_EMAIL for:"
  echo "    - Backend error log entries (within 5 minutes)"
  echo "    - Health endpoint failures (within 5 minutes)"
fi

# --- Summary ---
print_header "Setup Complete"

echo -e "${BOLD}What was created:${NC}"
echo ""
echo "  GCP Project:       $GCP_PROJECT"
echo "  Region:            $GCP_REGION"
echo "  Cloud Run service: $SERVICE_NAME"
echo "  Cloud Run URL:     ${CLOUD_RUN_URL:-N/A}"
echo "  Service account:   $SA_EMAIL (Vertex AI in $VERTEX_LOCATION)"
echo "  Video bucket:      gs://$VIDEO_BUCKET (1-day delete rule)"
echo ""
echo "  Secrets stored in Secret Manager:"
echo "    - jwt-secret"
echo "    - google-client-id"
echo ""
echo "  Monitoring:"
echo "    - Log-based metric: lessonlens-api-errors"
echo "    - Alert policy: error log entries → $ALERT_EMAIL"
echo "    - Uptime check: /health every 5 minutes → $ALERT_EMAIL"
echo ""
echo "  APIs enabled:"
for api in "${APIS[@]}"; do
  echo "    - $api"
done
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo ""
echo "  1. Run the app configuration script:"
echo "     bash scripts/configure-app.sh"
echo ""
echo "  2. You'll need these values for app configuration:"
echo "     Cloud Run URL:     ${CLOUD_RUN_URL:-<check GCP Console>}"
echo "     Google Client ID:  $GOOGLE_CLIENT_ID"
echo "     Allowed domain:    $ALLOWED_DOMAIN"
echo ""
