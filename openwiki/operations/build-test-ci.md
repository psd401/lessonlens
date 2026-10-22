---
type: Runbook
title: Build, test and CI commands
description: Verified commands for building and testing the Cloud Run backend and the macOS app, what CI does and does not cover (only the backend gate), dependency-pin warnings, and which checks are conditional.
tags: [build, test, ci, bun, xcodebuild, github-actions]
openwiki:
  roles: [testing, operations, delivery]
  change_kinds: [validation, ci]
  source_paths:
    - .github/workflows/psd-ci.yml
    - .github/workflows/psd-ci-jobs.yml
    - .github/workflows/security-scan.yml
    - .github/workflows/license-check.yml
    - .github/workflows/claude-review.yml
    - .github/workflows/openwiki-update.yml
    - CloudRunBackend/package.json
    - CloudRunBackend/tests/test-env.ts
    - LessonLens/LessonLensTests
    - CLAUDE.md
  test_paths:
    - CloudRunBackend/tests
    - LessonLens/LessonLensTests
  invariants:
    - The backend uses bun only (never npm/npx) and CI uses frozen lockfiles.
    - CI gates must not be weakened (no removing tests, loosening gates, or allow-no-tests on backend jobs).
    - CI covers only the Cloud Run backend; the Swift app is not in CI, so app changes need a local macOS build and test run.
  validation_commands:
    - cd CloudRunBackend && bun test
    - cd CloudRunBackend && bun test tests/prompt-wording.test.ts
    - xcodebuild -project LessonLens/LessonLens.xcodeproj -scheme LessonLens -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
---

# Build, test and CI commands

Sources of truth: `CLAUDE.md` (verified commands, anti-patterns), `CloudRunBackend/package.json`, `.github/workflows/`.

## Backend (Bun)

| Task | Command | Notes |
|---|---|---|
| Install exactly the lockfile | `cd CloudRunBackend && bun install --frozen-lockfile` | `bun.lock` exists but is outside the wiki's readable scope |
| Type/bundle check | `cd CloudRunBackend && bun run build` | `bun build src/index.ts --outdir=dist --target=bun` |
| Tests | `cd CloudRunBackend && bun test` | Add a file path to narrow, e.g. `bun test tests/video-routes.test.ts` |
| Local server | `cd CloudRunBackend && bun run dev` | needs `JWT_SECRET` (>= 32 chars), `GOOGLE_CLIENT_ID`, and Gemini config - see [Cloud Run API](../backend/cloud-run-api.md) |

Test harness facts that trip people up: Cloud Run tests must `import './test-env'` before importing `../src/index` because `index.ts` reads env at import time and bun shares one module registry across test files (`tests/test-env.ts` sets a CI `JWT_SECRET`, `GOOGLE_CLIENT_ID`, `VIDEO_BUCKET`, and a high `VIDEO_RATE_LIMIT_PER_HOUR` because all route tests share one in-memory limiter). Route tests replace `globalThis.fetch` with a fake metadata server / Cloud Storage / Vertex (`video-routes.test.ts`) and mint session JWTs with `jose`; unexpected URLs throw.

Suites, and the behaviour each one owns:

- `index.test.ts`: `HTTP surface`, `rate limiter`, and `startup validation` (the last one imports `src/index.ts` in a subprocess via `Bun.spawnSync`).
- `gemini-client.test.ts`: `vertex backend`, `config helpers` (Vertex endpoint URLs and metadata-server auth).
- `gemini-logging.test.ts`: `unusable Gemini replies are logged without their content` (no reply content in `console.error`; see [Cloud Run API](../backend/cloud-run-api.md)).
- `video-storage.test.ts`: `object names` and `Cloud Storage requests`.
- `video-routes.test.ts`: `POST /upload/initiate/gcs` and `POST /analyze/video with gcsObject`.
- `prompt-wording.test.ts`: `prompt wording stays coaching, not evaluation`. It imports the builders from `shared/prompts` directly (not through a route) and uses no fake fetch. Run it alone after editing prompt templates.
- `prompt-builder.test.ts`: `analysis prompt`, `chat prompt`. It pins escaping of user content inside data tags (see [shared prompts](../backend/shared-prompts.md)); also imports the builders directly.
- `input-limits.test.ts`: `/analyze field caps`, `/analyze/video field caps`, `/chat field caps`, `total body cap`. Real requests through the server that assert 400/413 and zero Gemini calls; see [input size limits](../backend/input-limits.md).

## macOS app

- Build: `xcodebuild -project LessonLens/LessonLens.xcodeproj -scheme LessonLens -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`, then launch the Debug app and check for dyld errors.
- Test: same command with `test`; narrow with `-only-testing:LessonLensTests/<Class>`. The `LessonLensTests` target is app-hosted and run by the shared scheme. Existing classes: `InterruptedProcessingTests`, `PauseDetectionTests`, `PauseBackfillTests`, `VideoAnalysisServiceTests`, `MarkdownParserTests`, `PersistentStoreTests`, `MediaCleanupTests` (see [app overview](../app/overview.md) for the invariants they pin, and [persistent store](../app/persistent-store.md) for the store-recovery suite).
- Needs `LessonLens/Config/Local.xcconfig` to sign in at runtime (not to compile); see [auth and config](../app/auth-and-config.md).
- **Dependency pins:** WhisperKit is a Swift package declared in the Xcode project; the `Package.resolved` lockfile is committed. Do not run "Update to Latest Package Versions" or re-resolve without a clean build and launch test - swift-collections 1.7.0 crashed launch on macOS 26.7 / Xcode 27.0 (dyld `_swift_initBorrow`); 1.3.0 works. `LessonLens/Package.swift` is legacy and unused.

## CI

`.github/workflows/psd-ci.yml` runs on pull requests and pushes to `main` and only calls `.github/workflows/psd-ci-jobs.yml` (`workflow_call`). That file holds one service job, `psd-ci-cloudrun-backend`, which calls the org reusable workflow `PSD401/.github/.github/workflows/reusable-psd-ci.yml` with `working-directory: CloudRunBackend`. The reference is pinned to a commit SHA (`@1aa5f5351a78b15f5c71668037f5d35b9613ae41 # v1.0.0`), not a branch, so updating the org gate is a deliberate edit of that pin. A combined job named `psd-ci` (`if: always()`, `needs` the service job) fails unless every service job succeeded; because the caller job is also named `psd-ci`, the required check reports as `psd-ci / psd-ci`, so keep that naming when editing either file. The former Cloudflare job is gone ([Cloudflare Worker (removed)](../backend/cloudflare-worker.md)). A TODO in `psd-ci-jobs.yml` notes the Swift app is not covered (needs a macOS runner).

Other workflows: `security-scan.yml` (calls org `reusable-security-scan.yml`), `license-check.yml`, `claude-review.yml`, and `openwiki-update.yml`. All org reusable references are pinned to the same SHA as the backend gate. `openwiki-update.yml` runs on manual dispatch, on pushes to `main`, and weekly (`cron: "0 8 * * 1"`) by calling the org reusable `reusable-openwiki.yml`; it shares an `openwiki` concurrency group that cancels superseded runs, and the job needs `contents: write` and `pull-requests: write` granted by the caller. `.github/dependabot.yml` configures dependency update PRs.

Never weaken CI.

## Conditional / expensive checks

- Full Xcode build + launch: only when Swift code, project settings, entitlements, or package pins change.
- `bun run build`: when changing imports across `../../../shared` or Dockerfile layout (see [shared prompts](../backend/shared-prompts.md)).
- Docker image build / `gcloud` deploys: only for deployment changes ([deployment and release](deployment-and-release.md)); never as a routine check.
nd/shared-prompts.md)).
- Docker image build / `gcloud` deploys: only for deployment changes ([deployment and release](deployment-and-release.md)); never as a routine check.
