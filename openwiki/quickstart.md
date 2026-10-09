---
type: Quickstart
title: LessonLens wiki quickstart
description: Entry point for the LessonLens knowledge base - what the product and repository are, how this wiki is organized, a task-routing table from change intent to pages, source entry points, tests and validation commands, and the backlog of undocumented areas.
tags: [quickstart, navigation, lessonlens]
openwiki:
  roles: [repository]
  change_kinds: [navigation]
  source_paths:
    - README.md
    - CLAUDE.md
---

# LessonLens wiki quickstart

**What it is.** LessonLens is a voluntary, privacy-first AI coaching tool for Peninsula School District teachers: a native macOS app (SwiftUI + SwiftData, on-device WhisperKit transcription) that sends transcripts (or a temporary compressed video) through a stateless Bun/Hono proxy on Cloud Run to Gemini, then guides the teacher through reflection, a self-vs-AI comparison, and a coaching chat. It is **not** an evaluation tool; nobody but the teacher sees the data. Product rules and the data-flow diagram are in [architecture overview](architecture/overview.md).

**Repository map.** `LessonLens/` macOS app and its tests - `CloudRunBackend/` primary backend - `CloudflareWorker/` alternative backend - `shared/prompts/` prompt builders imported by both backends via `../../../shared` - `scripts/` setup, config, sign and package helpers - `docs/` deployment guide, terms/privacy text and the GitHub Pages help/history sites - root `Dockerfile`, `cloudbuild.yaml`, `RELEASING.md`. Source of truth for conventions is `CLAUDE.md`; this wiki is derived from source and tests (git history was not available when it was generated).

## Wiki map

| Section | Pages |
|---|---|
| Architecture | [System architecture and invariants](architecture/overview.md) |
| macOS app | [App overview, startup, data model](app/overview.md) - [Lesson workflow and status lifecycle](app/lesson-workflow.md) - [Auth and district config](app/auth-and-config.md) - [Frameworks and techniques](app/frameworks-and-techniques.md) - [Reflection, chat, export](app/reflection-chat-export.md) |
| Backend | [Cloud Run API](backend/cloud-run-api.md) - [Video analysis pipeline](backend/video-analysis-pipeline.md) - [Shared prompts](backend/shared-prompts.md) - [Cloudflare Worker](backend/cloudflare-worker.md) |
| Operations | [Build, test, CI](operations/build-test-ci.md) - [Deployment, release, public docs](operations/deployment-and-release.md) |

## Task routing

Run commands from the repository root. Backend tests are quiet-by-default with bun; Swift checks need macOS + Xcode and are not in CI.

| Change area / intent | Page | Entry points | Key symbols | Focused tests | Minimal validation |
|---|---|---|---|---|---|
| Add/change a Cloud Run endpoint, auth rule, rate limit, env var | [Cloud Run API](backend/cloud-run-api.md) | `CloudRunBackend/src/index.ts`, `src/routes/*.ts` | `env`, `checkRateLimit`, `verifySession`, `authRoutes` | `tests/index.test.ts` (HTTP surface, rate limiter, startup validation) | `cd CloudRunBackend && bun test tests/index.test.ts` |
| Gemini backend selection (API key vs Vertex), model, error handling | [Cloud Run API](backend/cloud-run-api.md) | `src/gemini-client.ts`, `src/gcp-auth.ts`, `src/gemini-error.ts` | `createGeminiClient`, `vertexHost`, `createMetadataAuth`, `describeGeminiError` | `tests/gemini-client.test.ts` | `cd CloudRunBackend && bun test tests/gemini-client.test.ts` |
| Video upload/analysis, Cloud Storage, ownership checks, deletion | [Video pipeline](backend/video-analysis-pipeline.md) | `src/routes/upload.ts`, `src/routes/analyze-video.ts`, `src/video-storage.ts`, `src/gemini-files.ts` | `createVideoStorage`, `isOwnedBy`, `userHash`, `videoMetadataFor`, `analyzeFromCloudStorage` | `tests/video-routes.test.ts`, `tests/video-storage.test.ts`, `tests/legacy-video-routes.test.ts` | `cd CloudRunBackend && bun test tests/video-routes.test.ts tests/video-storage.test.ts` |
| Edit prompt wording or the model JSON schema | [Shared prompts](backend/shared-prompts.md) | `shared/prompts/builder.ts`, `templates/*.ts`, `types.ts` | `buildAnalysisPrompt`, `buildVideoAnalysisPrompt`, `buildChatPrompt`, `RESPONSE_SCHEMA_*` | none dedicated (route tests use fake replies) | `cd CloudRunBackend && bun run build && bun test`; if schema changed also Swift tests |
| Change the Cloudflare alternative | [Cloudflare Worker](backend/cloudflare-worker.md) | `CloudflareWorker/src/index.ts`, `src/routes/*.ts`, `wrangler.toml` | `Env`, KV `RATE_LIMIT` | `tests/index.test.ts` | `cd CloudflareWorker && bun test` |
| Recording/import/transcription/analysis orchestration, statuses | [Lesson workflow](app/lesson-workflow.md) | `Features/Recording/RecordingDetailView.swift`, `Features/Transcription/TranscriptionService.swift`, `Features/Analysis/*Service.swift`, `Core/Models/Recording.swift` | `RecordingStatus`, `resetInterruptedProcessing`, `detectPauses`, `backfillMissingPauses`, `VideoAnalysisService.analyzeVideo` | `InterruptedProcessingTests`, `PauseDetectionTests`, `PauseBackfillTests`, `VideoAnalysisServiceTests` | `xcodebuild -project LessonLens/LessonLens.xcodeproj -scheme LessonLens -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:LessonLensTests/VideoAnalysisServiceTests` |
| SwiftData models, schema change, app startup, services wiring | [App overview](app/overview.md) | `App/LessonLensApp.swift`, `App/ServiceContainer.swift`, `Core/Models/*.swift` | `ModelContainer` schema list, `ServiceContainer`, `AppConfiguration.load` | `PauseBackfillTests`, `InterruptedProcessingTests` | build, then launch Debug app (schema errors reset the store) |
| Sign-in, tokens, Keychain, district config (`Local.xcconfig`) | [Auth and config](app/auth-and-config.md) | `Features/Authentication/AuthService.swift`, `Core/Services/KeychainService.swift`, `Config/*.xcconfig`, `Resources/Info.plist` | `AuthService.getValidSession`, `AppConfiguration.load`, `LL*` plist keys | none (manual sign-in) | `bash scripts/check-app-config.sh <built .app>` |
| Add/edit a teaching framework or technique | [Frameworks and techniques](app/frameworks-and-techniques.md) | `Core/Models/TeachingFramework.swift`, `Features/Techniques/FrameworkRegistry.swift`, `Frameworks/*.swift` | `TeachingFramework`, `FrameworkRegistry.techniques`, `Technique` | none | app build |
| Reflection wizard, coaching chat, PDF/Markdown export | [Reflection, chat, export](app/reflection-chat-export.md) | `Features/Reflection/*`, `Features/Chat/ChatService.swift`, `ChatPanelView.swift`, `Features/Export/ExportService.swift` | `ReflectionFlowView`, `ChatService.formatTimestampedTranscript`, `PDFPagePacker.packIntoPages` | `MarkdownParserTests` | `xcodebuild ... test -only-testing:LessonLensTests/MarkdownParserTests` |
| Docker/Cloud Run deploy, signing, release, help/history sites | [Deployment and release](operations/deployment-and-release.md) | `CloudRunBackend/Dockerfile`, `cloudbuild.yaml`, `scripts/*.sh`, `RELEASING.md`, `docs/help/help-steps.js`, `docs/history/history.js` | n/a | n/a | `bash scripts/check-app-config.sh <app>`; deploys are conditional/manual |
| CI, dependency pins, test commands | [Build, test, CI](operations/build-test-ci.md) | `.github/workflows/psd-ci.yml`, `package.json` files | n/a | all suites | see page |

### Cross-boundary reminders

- A wire-contract change (request/response key, new field) spans: template in `shared/prompts/templates/components.ts` -> route mapper -> Swift Codable structs -> SwiftData model. Verify with backend tests plus the Swift `VideoAnalysisServiceTests`; there is no automated end-to-end test, so smoke-test against a dev backend when the contract changes.
- The shipped surface for the backend is the Docker image built from the repo root (`shared/` must be copied); a change that typechecks inside `CloudRunBackend/` can still break the image if the `../../../shared` layout moves. Conditional check: `cd CloudRunBackend && bun run build`.
- The macOS app's real consumer-facing configuration comes from `Local.xcconfig` -> `Info.plist` -> `AppConfiguration.load()`; a feature that "works in tests" can still fail sign-in if the keys are empty.

## Backlog

Areas identified but not given dedicated coverage (source anchor - reason):

- Theme and shared UI (`LessonLens/LessonLens/Core/Theme/`, `Core/Views/ContentView.swift` sidebar/welcome views) - presentational, low change-risk; only navigation structure is described in [app overview](app/overview.md).
- `HowItWorksView`, `TermsAndPrivacyView`, `SettingsView`, `GrowthDashboardView` (`LessonLens/LessonLens/Features/`) - covered only by mention; read the source if editing copy or charts.
- `scripts/setup.sh` monitoring/alerting section - summarized, not step-by-step; see `docs/DEPLOYMENT.md` (partly stale versus the Vertex/Cloud Storage path).
- `CloudRunBackend` bucket and IAM provisioning - infrastructure is not in the repository, so it cannot be documented from source.
- Git history and `.xcodeproj` build settings (`project.pbxproj`) - not available to this generation run (history excluded by `.openwikiignore` rules; project file not inspected).
