# LessonLens District Deployment Guide

This guide walks your district through deploying LessonLens — a macOS app that uses AI to help teachers reflect on classroom instruction. The deployment has two main parts: a lightweight backend API on Google Cloud, and the macOS app distributed to teacher laptops.

---

## Tier 1: What You Need (For Tech Directors)

Before involving your IT team, review these prerequisites and decisions.

### Prerequisites Checklist

| Requirement | Details | Your Value |
|-------------|---------|------------|
| **Google Workspace** | District must use Google Workspace for Education | Domain: `____________` |
| **Google Cloud account** | A GCP billing account (free tier covers most usage) | Project ID: `____________` |
| **Gemini API key** | From Google AI Studio (ai.google.dev) | Key: `____________` |
| **Apple Developer account** | For signing and distributing the macOS app ($99/yr) | Team ID: `____________` |
| **MDM solution** | Mosyle, Jamf, Kandji, or similar for app distribution | MDM: `____________` |
| **macOS devices** | Teacher laptops running macOS 14 (Sonoma) or later | |
| **Git & Xcode** | IT staff need Xcode 15+ and Git installed on a Mac | |

### Cost Estimates

| Service | Estimated Monthly Cost | Notes |
|---------|----------------------|-------|
| Google Cloud Run | $0–15/mo | Scales to zero when idle; free tier covers light usage |
| Gemini API | $0.01–0.27/analysis | Text analysis ~$0.01; video analysis ~$0.27 per lesson |
| Apple Developer Program | $99/yr | Required for signing and notarization |
| **Total** | **~$5–20/mo + $99/yr** | For a typical district of 50–200 teachers |

### Decision Points

Before your IT team begins, decide:

1. **GCP Region**: Where should your backend run? Pick the region closest to your district.
   - `us-west1` (Oregon), `us-central1` (Iowa), `us-east1` (South Carolina), etc.
   - Your choice: `____________`

2. **Bundle ID prefix**: A reverse-domain identifier for your app (e.g., `com.mydistrict.lessonlens`).
   - Your choice: `____________`

3. **Branding**: Do you want to customize the app's login screen with your district name? (Optional — can be done later.)

4. **MDM distribution**: How will you push the app to teacher laptops?

### Timeline Expectations

| Phase | What happens |
|-------|-------------|
| Phase 1: Google Cloud Setup | Create project, enable APIs, get Gemini key |
| Phase 2: Backend Deployment | Run setup script or manual deployment |
| Phase 3: App Configuration | Run configure script, set signing identity |
| Phase 4: Build & Distribute | Archive in Xcode, notarize, push via MDM |

---

## Tier 2: Step-by-Step Deployment (For IT Staff)

### Phase 1: Google Cloud Setup

#### 1.1 Create a GCP Project

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Click **Select a project** → **New Project**
3. Name it something like `lessonlens` or `district-lessonlens`
4. Note your **Project ID** (not the project name — the ID shown below the name field)
5. Link a billing account (required for Cloud Run, but free tier covers most usage)

#### 1.2 Enable Required APIs

In the GCP Console, navigate to **APIs & Services → Enable APIs** and enable:

- Cloud Run Admin API
- Secret Manager API
- Artifact Registry API
- Cloud Build API

Or use the CLI:
```bash
gcloud services enable \
  run.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  --project YOUR_PROJECT_ID
```

#### 1.3 Get a Gemini API Key

1. Go to [ai.google.dev](https://ai.google.dev)
2. Click **Get API key** → **Create API key**
3. Select your GCP project
4. Copy and save the key securely — you'll need it for backend deployment

#### 1.4 Create Google OAuth Credentials

1. Go to **APIs & Services → Credentials** in GCP Console
2. Click **Create Credentials → OAuth client ID**
3. Application type: **iOS**
4. Bundle ID: Your chosen bundle ID (e.g., `com.mydistrict.lessonlens`)
5. Copy the **Client ID** — you'll need it for app configuration

> **Important**: The OAuth client type must be **iOS**, not Web. The macOS app uses the Google Sign-In SDK which requires an iOS-type credential.

### Phase 2: Backend Deployment

You have two options: use the automated setup script, or deploy manually.

#### Option A: Automated Setup (Recommended)

```bash
cd /path/to/lessonlens
bash scripts/setup.sh
```

The script will:
- Verify prerequisites (gcloud CLI, authentication, bun)
- Prompt for your project ID, region, email domain, and Gemini API key
- Enable required GCP APIs
- Generate a secure JWT secret
- Store secrets in Google Secret Manager
- Deploy the backend to Cloud Run
- Validate the deployment with a health check

Run with `--dry-run` to preview all steps without executing them.

#### Option B: Manual Deployment

If you prefer to run commands yourself:

**Step 1: Set your project**
```bash
gcloud config set project YOUR_PROJECT_ID
```

**Step 2: Create secrets**
```bash
# Generate a JWT secret
JWT_SECRET=$(openssl rand -base64 48)

# Store secrets in Secret Manager
echo -n "$JWT_SECRET" | gcloud secrets create jwt-secret --data-file=-
echo -n "YOUR_GEMINI_API_KEY" | gcloud secrets create gemini-api-key --data-file=-
echo -n "YOUR_GOOGLE_CLIENT_ID" | gcloud secrets create google-client-id --data-file=-
```

**Step 3: Deploy to Cloud Run**
```bash
gcloud run deploy lessonlens-api \
  --source ./CloudRunBackend \
  --region YOUR_REGION \
  --allow-unauthenticated \
  --set-secrets="JWT_SECRET=jwt-secret:latest,GEMINI_API_KEY=gemini-api-key:latest,GOOGLE_CLIENT_ID=google-client-id:latest" \
  --set-env-vars="ALLOWED_DOMAIN=yourdomain.org,RATE_LIMIT_PER_HOUR=20,GEMINI_TEXT_MODEL=gemini-3.8-flash,GEMINI_VIDEO_MODEL=gemini-3.8-flash,VIDEO_RATE_LIMIT_PER_HOUR=5,CHAT_RATE_LIMIT_PER_HOUR=50"
```

**Step 4: Verify deployment**
```bash
CLOUD_RUN_URL=$(gcloud run services describe lessonlens-api --region YOUR_REGION --format='value(status.url)')
curl -s "$CLOUD_RUN_URL" | python3 -m json.tool
```

Expected response:
```json
{
  "name": "LessonLens API",
  "version": "1.0.0",
  "status": "healthy",
  "runtime": "Cloud Run"
}
```

### Phase 3: App Configuration

#### Option A: Automated Configuration (Recommended)

```bash
cd /path/to/lessonlens
bash scripts/configure-app.sh
```

The script will:
- Prompt for your Cloud Run URL, Google Client ID, allowed domain, and bundle ID
- Update all Swift source files and the Xcode project
- Optionally update district branding (name and login text)
- Validate that no old references remain

#### Option B: Manual Configuration

If you prefer to make changes yourself, update these files:

**ServiceContainer.swift** — Core configuration:
```swift
static let backendURL = "https://YOUR-CLOUD-RUN-URL"
static let googleClientID = "YOUR-GOOGLE-CLIENT-ID"
static let allowedDomain = "yourdomain.org"
```

**Bundle ID** — Replace `com.peninsula.lessonlens` with your bundle ID in:
- `LessonLens.xcodeproj/project.pbxproj` (2 occurrences: Debug and Release)
- `AppState.swift` (keychain keys)
- `KeychainService.swift` (service name)
- `Recording.swift` (storage directory)
- `RecordingService.swift` (storage directory)
- `AudioImportService.swift` (storage directory)
- `VideoImportService.swift` (storage directory)
- `AudioExtractionService.swift` (storage directory)
- `SettingsView.swift` (display path)

**LoginView.swift** — District branding:
```swift
// Update district name and domain text
"Peninsula School District" → "Your District Name"
"@psd401.net" → "@yourdomain.org"
```

### Phase 4: Build, Sign & Distribute

#### 4.1 Open in Xcode

1. Open `LessonLens/LessonLens.xcodeproj` in Xcode
2. Select the **LessonLens** target
3. Under **Signing & Capabilities**:
   - Check **Automatically manage signing**
   - Select your Apple Developer team
   - Verify the bundle ID matches what you configured

#### 4.2 Build & Archive

1. Select **Product → Archive** (make sure the scheme is set to "Any Mac")
2. When the archive completes, click **Distribute App**
3. Choose **Developer ID** distribution (for distribution outside the App Store)
4. Select **Upload** to send to Apple for notarization
5. Wait for notarization to complete (usually 5–15 minutes)
6. Click **Export Notarized App** to get the `.app` bundle

#### 4.3 Package for MDM

1. Wrap the `.app` in a `.pkg` installer:
   ```bash
   pkgbuild --component /path/to/LessonLens.app \
     --install-location /Applications \
     LessonLens.pkg
   ```
2. Upload `LessonLens.pkg` to your MDM solution (Mosyle, Jamf, Kandji, etc.)
3. Assign to teacher devices/groups
4. Deploy

#### 4.4 Verify Installation

On a teacher's Mac:
1. The app should appear in `/Applications/LessonLens.app`
2. Launch it — the Google Sign-In screen should appear
3. Sign in with a `@yourdomain.org` account
4. The app should connect to your Cloud Run backend

---

## Optional: Branding Customization

You can customize the app's appearance without touching core functionality.

### Login Screen

In `Features/Authentication/LoginView.swift`:
- **District name**: Line displaying `"Peninsula School District"`
- **Domain prompt**: Line displaying `"Sign in with your @psd401.net account"`
- **Tagline**: `"Reflect, Analyze, Grow"` (optional to change)

### Colors and Theming

The app uses SwiftUI's standard color system. To customize:
- Search for `.accentColor` or `Color.accentColor` references
- Modify the asset catalog colors in `Assets.xcassets`

### App Icon

Replace the icon set in `LessonLens/Assets.xcassets/AppIcon.appiconset/`:
- Provide icons at required sizes (16, 32, 128, 256, 512, 1024 px)
- Update `Contents.json` if filenames differ

---

## Troubleshooting

### Backend Issues

| Problem | Solution |
|---------|----------|
| Health check returns error | Check Cloud Run logs: `gcloud run services logs read lessonlens-api --region REGION` |
| "JWT_SECRET must be at least 32 characters" | Re-create the secret: the value is too short or empty |
| 401 on login | Verify GOOGLE_CLIENT_ID matches your OAuth credential and the domain in ALLOWED_DOMAIN matches your Google Workspace domain |
| Rate limit errors | Increase RATE_LIMIT_PER_HOUR env var on Cloud Run |
| Gemini API errors | Verify your API key is valid and has the Generative Language API enabled |

### App Issues

| Problem | Solution |
|---------|----------|
| "Domain not allowed" on login | Check `allowedDomain` in ServiceContainer.swift matches your Google Workspace domain |
| Google Sign-In fails | Verify the OAuth Client ID bundle ID matches your app's bundle ID exactly |
| Can't connect to backend | Check the `backendURL` in ServiceContainer.swift — try `curl`-ing it from Terminal |
| Recordings not saving | Check disk permissions for `~/Library/Application Support/your.bundle.id/` |
| Code signing errors in Xcode | Ensure your Apple Developer team is selected and provisioning profiles are current |

### Deployment Script Issues

| Problem | Solution |
|---------|----------|
| `gcloud: command not found` | Install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install |
| `bun: command not found` | Install Bun: `curl -fsSL https://bun.sh/install \| bash` |
| Permission denied on script | Run `chmod +x scripts/setup.sh scripts/configure-app.sh` |
| Script fails midway | Scripts are idempotent — fix the issue and re-run |

---

## Architecture Overview

```
┌─────────────────────┐     HTTPS      ┌──────────────────────┐
│   LessonLens App    │ ◄────────────► │   Cloud Run Backend  │
│   (macOS, Swift)    │                │   (Bun + Hono)       │
│                     │                │                      │
│  - Records lessons  │                │  - Google OAuth auth │
│  - Sends audio/video│                │  - Gemini API proxy  │
│  - Displays analysis│                │  - Rate limiting     │
└─────────────────────┘                └──────────┬───────────┘
                                                  │
                                                  ▼
                                       ┌──────────────────────┐
                                       │   Google Gemini API   │
                                       │   (AI Analysis)       │
                                       └──────────────────────┘
```

**Key design points:**
- The backend acts as an authenticated proxy to Gemini — it never stores lesson content
- All audio/video processing happens on-device or via Gemini's API
- No student data is collected or transmitted — only teacher instruction is analyzed
- Rate limiting prevents runaway API costs
- Each district runs its own isolated backend instance

---

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `JWT_SECRET` | Yes | — | Secret for signing auth tokens (min 32 chars) |
| `GEMINI_API_KEY` | Yes | — | Google Gemini API key |
| `GOOGLE_CLIENT_ID` | Yes | — | OAuth client ID for Google Sign-In |
| `ALLOWED_DOMAIN` | No | `psd401.net` | Google Workspace domain to restrict login |
| `RATE_LIMIT_PER_HOUR` | No | `20` | Text analysis rate limit per user |
| `VIDEO_RATE_LIMIT_PER_HOUR` | No | `5` | Video analysis rate limit per user |
| `CHAT_RATE_LIMIT_PER_HOUR` | No | `50` | Chat rate limit per user |
| `GEMINI_TEXT_MODEL` | No | `gemini-3.8-flash` | Model for text analysis |
| `GEMINI_VIDEO_MODEL` | No | `gemini-3.8-flash` | Model for video analysis |
| `PORT` | No | `8080` | Server port (set automatically by Cloud Run) |

---

## Included Observation Frameworks

Every deployment ships with these 7 instructional frameworks — no configuration needed:

1. **Danielson Framework for Teaching** — 4 domains, 22 components
2. **Marzano Focused Teacher Evaluation** — 4 domains, 23 elements
3. **NIET Teaching Standards** — 5 standards, rubric-based
4. **5D+ Teacher Evaluation** — 5 dimensions, sub-dimensions
5. **Marshall's Teacher Evaluation** — 6 domains, mini-observation focus
6. **Project GLAD** — Guided Language Acquisition Design strategies
7. **PSD Essentials** — Peninsula School District's instructional framework
