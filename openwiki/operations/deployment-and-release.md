---
type: Runbook
title: Deployment, release and public docs
description: How the backend is containerised and deployed to Cloud Run, how district deployments are bootstrapped with the setup scripts, how the signed macOS pkg release is produced, and how the GitHub Pages help/history sites are kept current.
tags: [deployment, cloud-run, docker, release, notarization, jamf, github-pages]
openwiki:
  roles: [operations, delivery]
  change_kinds: [deployment, release, docs-site]
  source_paths:
    - CloudRunBackend/Dockerfile
    - Dockerfile
    - cloudbuild.yaml
    - scripts/setup.sh
    - scripts/configure-app.sh
    - scripts/check-app-config.sh
    - scripts/sign-and-package.sh
    - scripts/package.sh
    - scripts/notarize-pkg.sh
    - RELEASING.md
    - docs/DEPLOYMENT.md
    - docs/help/help-steps.js
    - docs/history/history.js
    - LessonLens/expected-entitlements.txt
  invariants:
    - The Docker build context is the repo root and must copy shared/ so ../../../shared imports resolve.
    - Release builds are unsandboxed on purpose; do not add the app sandbox without a data-migration plan.
    - Public docs use sample data only and plain language.
  validation_commands:
    - bash scripts/check-app-config.sh /path/to/LessonLens.app
---

# Deployment, release and public docs

Most of this page is operator-facing; consult it when changing Dockerfiles, scripts, signing, release notes, or `docs/`. For day-to-day code validation use [build, test and CI](build-test-ci.md).

## Backend container

- `CloudRunBackend/Dockerfile` (used by `cloudbuild.yaml`, `-f CloudRunBackend/Dockerfile .` from the repo root): `oven/bun:1`, copies `shared/` to `/app/shared`, installs production deps with `bun install --frozen-lockfile --production` in `/app/CloudRunBackend`, copies `src`, runs `bun run src/index.ts` on port 8080. The layout is what keeps the relative `../../../shared/prompts` imports working ([shared prompts](../backend/shared-prompts.md)).
- The root `Dockerfile` is an equivalent variant (also copies `shared` to `/app/shared`, sets `NODE_ENV=production`); `.gcloudignore` files exist at root and in `CloudRunBackend/`. `cloudbuild.yaml` pushes `lessonlens-api:v1.4.2` and `:latest` to Artifact Registry in `us-west1` - the version tag is hard-coded there and must be bumped by hand.
- Runtime configuration (secrets, `VIDEO_BUCKET`, `GEMINI_BACKEND`, etc.) is environment-only; see [Cloud Run API](../backend/cloud-run-api.md). The bucket (private, 1-day lifecycle rule) and the service account's Vertex/Storage permissions are infrastructure that is **not** defined in this repo's code ([video pipeline](../backend/video-analysis-pipeline.md)); `docs/DEPLOYMENT.md` is the operator guide and predates the Vertex/Cloud Storage path in places (it also says the app uses the Google Sign-In SDK, whereas the code uses `ASWebAuthenticationSession` - see [auth and config](../app/auth-and-config.md)). Prefer source and the backend README where they disagree.
- The Cloudflare alternative deploys with `wrangler deploy` and a KV namespace ([Cloudflare Worker](../backend/cloudflare-worker.md)).

## District bootstrap scripts

- `scripts/setup.sh`: interactive (supports dry run) wizard that checks `gcloud`/auth, sets the project, enables APIs, stores secrets in Secret Manager, runs `gcloud run deploy`, and optionally creates monitoring (log-based error metric, alert policy, uptime check).
- `scripts/configure-app.sh`: writes the git-ignored `LessonLens/Config/Local.xcconfig` (and can rebrand the login-screen district name); `--dry-run` previews. Config keys and their effect on the app: [auth and config](../app/auth-and-config.md).

## macOS release

Per `RELEASING.md`: releases are built from `origin/main`, signed, notarized and packaged with the `psd-sign` skill, then published as a GitHub Release with one `.pkg` (tag `v<MARKETING_VERSION>`, digits and dots only; pkg identifier `net.psd401.lessonlens` - keep it). PSD IT's AutoPkg recipe picks up `/releases/latest` and deploys via Jamf.

Checklist: ensure `Local.xcconfig` exists on the build Mac; bump `MARKETING_VERSION` (Debug and Release) in a merged PR; run `scripts/check-app-config.sh` on the archived app (the `psd-sign` path archives with `xcodebuild` and does not call the repo scripts); update `docs/help/help-steps.js` and `docs/history/history.js`.

The repo scripts are the generic path: `sign-and-package.sh` (sign -> notarize -> staple -> package -> notarize pkg -> verify; takes `APPLE_TEAM_ID`/`APPLE_DEVELOPER_NAME` from env or prompts), `package.sh` (signed `.pkg`; `PKG_BUNDLE_ID` defaults to a placeholder), `notarize-pkg.sh`. Both packaging scripts run `check-app-config.sh`, which rejects empty `LL*` values or the placeholder bundle id.

**Sandbox decision:** Release uses `Resources/LessonLens-Release.entitlements` (hardened runtime, only `com.apple.security.device.audio-input`; matches `LessonLens/expected-entitlements.txt`) and is deliberately **not sandboxed** so existing teacher data under `~/Library/Application Support` stays visible; Debug uses the sandboxed `LessonLens.entitlements`. Moving to the sandbox needs a container-migration plan tested on a copy of real data (`RELEASING.md`). SwiftData store handling also matters here ([app overview](../app/overview.md)).

## Public docs (`docs/`, GitHub Pages)

- `docs/history/` (project timeline, content in `history.js`) and `docs/help/` (teacher tutorial with driver.js tours; labels and hotspot positions in `help-steps.js`, screenshots in `docs/help/img/`). Edit the `.js` data, not the HTML. Audience is non-developers: no "commits" or infrastructure jargon.
- Per release or user-visible UI change: add a history stop and update `currentVersions`/`updated`; re-check quoted UI labels against app source, update `appVersion`/`updated`, recapture changed screenshots and re-position hotspots. Screenshots use sample data only, with the sidebar session list blurred below the samples. Source: `CLAUDE.md`.
- `docs/TERMS_AND_PRIVACY_DRAFT.md` is the terms/privacy text referenced by the README and surfaced in-app by `TermsAndPrivacyView`. Other `*-draft.md` and `press-kit-draft/` files are productization collateral, not app behavior, and are not documented here.
- All copy must stay "coaching, not evaluation" ([architecture overview](../architecture/overview.md)).

## Guardrails

Public repo: never commit infrastructure identifiers (backend URL/project number, OAuth client ID, Apple Team ID) to source, `Info.plist`, or `project.pbxproj`; keep them in `Local.xcconfig`. Never reintroduce dev auth bypasses. `.gitleaksignore` and the `security-scan.yml` workflow exist for secret scanning.
