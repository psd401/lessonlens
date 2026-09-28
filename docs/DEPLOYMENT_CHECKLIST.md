# LessonLens Deployment Checklist

Print this page and check off each step as you complete it. Fill in your values in the blanks.

---

## Your District Configuration

| Field | Value |
|-------|-------|
| GCP Project ID | ______________________________ |
| GCP Region | ______________________________ |
| Google Workspace Domain | ______________________________ |
| Bundle ID | ______________________________ |
| Gemini API Key | ______________________________ |
| Google OAuth Client ID | ______________________________ |
| Cloud Run URL | ______________________________ |
| Apple Developer Team ID | ______________________________ |
| MDM Solution | ______________________________ |

---

## Phase 1: Google Cloud Setup

- [ ] Created GCP project: `________________________`
- [ ] Linked billing account
- [ ] Enabled Cloud Run Admin API
- [ ] Enabled Secret Manager API
- [ ] Enabled Artifact Registry API
- [ ] Enabled Cloud Build API
- [ ] Created Gemini API key at ai.google.dev
- [ ] Created OAuth Client ID (type: **iOS**, bundle ID matches above)

## Phase 2: Backend Deployment

**Option A — Script** (recommended):
- [ ] Ran `bash scripts/setup.sh`
- [ ] Verified health check passed

**Option B — Manual:**
- [ ] Set project: `gcloud config set project PROJECT_ID`
- [ ] Generated JWT secret: `openssl rand -base64 48`
- [ ] Stored `jwt-secret` in Secret Manager
- [ ] Stored `gemini-api-key` in Secret Manager
- [ ] Stored `google-client-id` in Secret Manager
- [ ] Deployed to Cloud Run: `gcloud run deploy lessonlens-api ...`
- [ ] Verified health check: `curl CLOUD_RUN_URL` → returns `"healthy"`

Cloud Run URL: `________________________________________`

## Phase 3: App Configuration

**Option A — Script** (recommended):
- [ ] Ran `bash scripts/configure-app.sh`
- [ ] Confirmed `LessonLens/Config/Local.xcconfig` was written with your values

**Option B — Manual:**
- [ ] Copied `LessonLens/Config/Local.example.xcconfig` to `Local.xcconfig`
- [ ] Set `LL_BUNDLE_ID`, `LL_DEVELOPMENT_TEAM`, `LL_BACKEND_HOST`, `LL_GOOGLE_CLIENT_ID_PREFIX`, `LL_ALLOWED_DOMAIN`
- [ ] (Optional) Updated district name in `LoginView.swift`
- [ ] Stored a backup copy of `Local.xcconfig` (it is git-ignored)

## Phase 4: Build, Sign & Distribute

- [ ] Opened `LessonLens.xcodeproj` in Xcode
- [ ] Verified bundle ID matches: `________________________`
- [ ] Built successfully (Product → Build)
- [ ] Archived (Product → Archive)
- [ ] Submitted for notarization (Distribute App → Developer ID → Upload)
- [ ] Notarization succeeded
- [ ] Exported notarized `.app`
- [ ] Packaged as `.pkg`: `pkgbuild --component ... --install-location /Applications LessonLens.pkg`
- [ ] Uploaded `.pkg` to MDM
- [ ] Assigned to teacher devices/groups
- [ ] Deployed via MDM

## Phase 5: Verification

- [ ] App launches on a teacher's Mac
- [ ] Google Sign-In screen appears
- [ ] Login with `@________________________` account succeeds
- [ ] App connects to backend (no connection errors)
- [ ] Test recording works (record 5+ minutes)
- [ ] Analysis completes successfully
- [ ] Chat follow-up works

## Optional: Branding

- [ ] Updated district name on login screen
- [ ] Updated domain display text
- [ ] Replaced app icon (if desired)
- [ ] Updated accent colors (if desired)

---

**Deployment completed by:** ______________________________ **Date:** ______________

**Notes:**

______________________________________________________________________

______________________________________________________________________

______________________________________________________________________
