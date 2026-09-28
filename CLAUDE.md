# LessonLens — Claude project notes

Privacy-first AI coaching tool for PSD teachers (native macOS, Apple Silicon). Record/import a lesson → on-device WhisperKit transcription → Gemini analysis → self-reflection wizard → coaching chat. **Voluntary; explicitly NOT an evaluation tool** — no administrator/evaluator ever sees a teacher's data. Domain-locked to @psd401.net.

## Layout
- `LessonLens/` — the macOS app: `LessonLens.xcodeproj` and app sources. SwiftUI + SwiftData; WhisperKit for on-device transcription. `LessonLens/Package.swift` is a legacy manifest, unused by the Xcode build. Unit tests live in `LessonLens/LessonLensTests/` (the `LessonLensTests` target, hosted by the app and run by the shared scheme's test action).
- `CloudRunBackend/` — Bun + Hono backend service (Cloud Run; `Dockerfile` + `cloudbuild.yaml` live at repo root).
- `CloudflareWorker/` — Bun + Hono stateless proxy; stores nothing.
- `shared/` — shared contracts/assets. `shared/prompts/` holds prompt builders both backends import via `../../../shared` relative paths; the `Dockerfile` copies `shared/` to preserve them, so don't change those import paths. `scripts/` — build/sign/package/notarize helpers.
- Many `*-draft.md` / `press-kit-draft` files in the tree are productization collateral, not app code.

## Build / release
- App: open `LessonLens/LessonLens.xcodeproj` in Xcode (or `xcodebuild`). The Xcode project declares WhisperKit as a Swift package; its lockfile, `LessonLens.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, is committed.
- Verify a build: `xcodebuild -project LessonLens/LessonLens.xcodeproj -scheme LessonLens -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`, then launch the Debug app to check for dyld errors. Run unit tests with the same command and `test` in place of `build`.
- Dependency pins: don't run Xcode's "Update to Latest Package Versions" or re-resolve without a clean build plus launch test. swift-collections 1.7.0 crashed the app at launch on macOS 26.7 / Xcode 27.0 (dyld "Symbol not found: _swift_initBorrow"); 1.3.0 works.
- Backends (bun only, never npm/npx): `cd CloudRunBackend && bun install --frozen-lockfile && bun run build && bun test`; `cd CloudflareWorker && bun install --frozen-lockfile && bun test`.
- CI: `.github/workflows/psd-ci.yml` runs the org reusable gate once per backend directory. The Swift app is not in CI (needs a macOS runner). Never weaken CI: don't remove or skip tests, loosen gates, or add `allow-no-tests` to the backend jobs.
- Signing / notarization / packaging: `scripts/sign-and-package.sh`, `scripts/notarize-pkg.sh`, `scripts/package.sh`. `sign-and-package.sh` and `package.sh` run `scripts/check-app-config.sh`, which rejects a built app with empty config values. The `psd-sign` skill covers the Jamf/Installomator release path; it archives with `xcodebuild` directly and does not call these scripts, so run `scripts/check-app-config.sh` on the archived app before signing.
- District config: bundle ID, Apple team, backend host, Google OAuth client ID prefix, and allowed domain come from `LessonLens/Config/Local.xcconfig` (git-ignored; template `Local.example.xcconfig`; `scripts/configure-app.sh` writes it). `Shared.xcconfig` includes it and feeds Info.plist `LL*` keys read by `AppConfiguration.load()`. Without it the app builds but cannot sign in, so every checkout and release build needs a copy.

## Conventions & guardrails
- Public repo: never hardcode infrastructure identifiers (backend URL/project number, OAuth client ID, Apple Team ID) in source, Info.plist, or project.pbxproj; they belong in `Local.xcconfig`. Never reintroduce dev auth bypasses. (The dev bypass and script identifiers were removed in March 2026; the app-source identifiers stayed until the September 2026 xcconfig move and remain in git history.)
- The proxy/worker stores no user data; analysis runs through Gemini; transcription stays on-device. Keep it that way.
- Backend: `JWT_SECRET` must stay >= 32 chars (`CloudRunBackend/src/index.ts` enforces it at startup). Rate limiting is in-memory by design; read the comments in `CloudRunBackend/src/index.ts` before changing it.
- All copy must stay "coaching, not evaluation."
- Current phase is largely non-code: productization, cross-platform porting, press/blog drafts. Discuss before editing app code.

## Public docs pages (`docs/`, GitHub Pages)
- `docs/history/`: project timeline for external audiences. Content lives in `history.js`.
- `docs/help/`: visual teacher tutorial with driver.js tours. Content, UI labels, and hotspot positions live in `help-steps.js`; screenshots in `docs/help/img/`.
- Edit the `.js` data files, not the HTML, for routine updates. Audience is non-developers: plain language, no "commits" or infrastructure jargon.
- Update checklist, run at each app release, backend version bump, or user-visible UI change:
  - History: add a stop for notable releases/milestones; update `currentVersions` and `updated`; keep claims tied to git log or GitHub Releases.
  - Help: re-check quoted UI labels against the app source; update `appVersion` and `updated`; recapture any screenshot whose screen changed and re-position its hotspots.
- Screenshots: sample data only (fictional lessons and student names). Blur the sidebar session list below the sample sessions so real session titles are never published. Never reuse captures of real lessons.
- Known gaps (Sep 2026): Growth step and Capture step still need sample-data screenshots.
