---
type: Runbook
title: Build, test and CI commands
description: Verified commands for building and testing the Bun backends and the macOS app, what CI does and does not cover, dependency-pin warnings, and which checks are conditional.
tags: [build, test, ci, bun, xcodebuild, github-actions]
openwiki:
  roles: [testing, operations, delivery]
  change_kinds: [validation, ci]
  source_paths:
    - .github/workflows/psd-ci.yml
    - CloudRunBackend/package.json
    - CloudflareWorker/package.json
    - CloudRunBackend/tests/test-env.ts
    - LessonLens/LessonLensTests
    - CLAUDE.md
  test_paths:
    - CloudRunBackend/tests
    - CloudflareWorker/tests
    - LessonLens/LessonLensTests
  invariants:
    - Backends use bun only (never npm/npx) and CI uses frozen lockfiles.
    - CI gates must not be weakened (no removing tests, loosening gates, or allow-no-tests on backend jobs).
    - The Swift app is not in CI; app changes need a local macOS build and test run.
  validation_commands:
    - cd CloudRunBackend && bun test
    - cd CloudflareWorker && bun test
    - xcodebuild -project LessonLens/LessonLens.xcodeproj -scheme LessonLens -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
---

# Build, test and CI commands

Sources of truth: `CLAUDE.md` (verified commands, anti-patterns), each `package.json`, `.github/workflows/`.

## Backends (Bun)

| Task | Command | Notes |
|---|---|---|
| Install exactly the lockfile | `cd CloudRunBackend && bun install --frozen-lockfile` (same in `CloudflareWorker`) | `bun.lock` files exist but are outside the wiki's readable scope |
| Type/bundle check | `cd CloudRunBackend && bun run build` | `bun build src/index.ts --outdir=dist --target=bun`; the worker has no build script |
| Tests | `bun test` in each directory | Add `--bail` or a file path to narrow, e.g. `bun test tests/video-routes.test.ts` |
| Local server | `cd CloudRunBackend && bun run dev` | needs `JWT_SECRET` (>= 32 chars), `GOOGLE_CLIENT_ID`, and Gemini config - see [Cloud Run API](../backend/cloud-run-api.md) |

Test harness facts that trip people up: Cloud Run tests must `import './test-env'` before importing `../src/index` because `index.ts` reads env at import time and bun shares one module registry across test files (`tests/test-env.ts` sets a CI `JWT_SECRET`, `GOOGLE_CLIENT_ID`, `VIDEO_BUCKET`, and a high `VIDEO_RATE_LIMIT_PER_HOUR` because all route tests share one in-memory limiter). Route tests replace `globalThis.fetch` with a fake metadata server / Cloud Storage / Vertex (`video-routes.test.ts`) or Gemini Files API (`legacy-video-routes.test.ts`) and mint session JWTs with `jose`; unexpected URLs throw. Suites: `index.test.ts` (HTTP surface, rate limiter, startup validation), `gemini-client.test.ts`, `video-storage.test.ts`, `video-routes.test.ts`, `legacy-video-routes.test.ts`. The worker has a single starter suite (`worker HTTP surface`). Details per area: [Cloud Run API](../backend/cloud-run-api.md), [video pipeline](../backend/video-analysis-pipeline.md), [Cloudflare Worker](../backend/cloudflare-worker.md).

## macOS app

- Build: `xcodebuild -project LessonLens/LessonLens.xcodeproj -scheme LessonLens -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`, then launch the Debug app and check for dyld errors.
- Test: same command with `test`; narrow with `-only-testing:LessonLensTests/<Class>`. The `LessonLensTests` target is app-hosted and run by the shared scheme. Existing classes: `InterruptedProcessingTests`, `PauseDetectionTests`, `PauseBackfillTests`, `VideoAnalysisServiceTests`, `MarkdownParserTests` (see [app overview](../app/overview.md) for the invariants they pin).
- Needs `LessonLens/Config/Local.xcconfig` to sign in at runtime (not to compile); see [auth and config](../app/auth-and-config.md).
- **Dependency pins:** WhisperKit is a Swift package declared in the Xcode project; the `Package.resolved` lockfile is committed. Do not run "Update to Latest Package Versions" or re-resolve without a clean build and launch test - swift-collections 1.7.0 crashed launch on macOS 26.7 / Xcode 27.0 (dyld `_swift_initBorrow`); 1.3.0 works. `LessonLens/Package.swift` is legacy and unused.

## CI

`.github/workflows/psd-ci.yml` runs the org reusable workflow `PSD401/.github/.github/workflows/reusable-psd-ci.yml@main` twice, with `working-directory: CloudRunBackend` and `CloudflareWorker`, on pull requests and pushes to `main`. A TODO in the file notes the Swift app is not covered (needs a macOS runner). Other workflows: `security-scan.yml`, `license-check.yml`, `claude-review.yml`, `openwiki-update.yml` (weekly/push-to-main wiki refresh via an org reusable workflow), plus `dependabot.yml`. Never weaken CI.

## Conditional / expensive checks

- Full Xcode build + launch: only when Swift code, project settings, entitlements, or package pins change.
- `bun run build`: when changing imports across `../../../shared` or Dockerfile layout (see [shared prompts](../backend/shared-prompts.md)).
- Docker image build / `gcloud` deploys: only for deployment changes ([deployment and release](deployment-and-release.md)); never as a routine check.
