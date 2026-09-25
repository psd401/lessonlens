# LessonLens — Claude project notes

Privacy-first AI coaching tool for PSD teachers (native macOS, Apple Silicon). Record/import a lesson → on-device WhisperKit transcription → Gemini analysis → self-reflection wizard → coaching chat. **Voluntary; explicitly NOT an evaluation tool** — no administrator/evaluator ever sees a teacher's data. Domain-locked to @psd401.net.

## Layout
- `LessonLens/` — the macOS app: `LessonLens.xcodeproj`, `Package.swift` (SPM deps), app sources, and `LessonLensTests/`. SwiftUI + SwiftData; WhisperKit for on-device transcription.
- `CloudRunBackend/` — backend service (Cloud Run; `Dockerfile` + `cloudbuild.yaml` live at repo root).
- `CloudflareWorker/` — stateless proxy; stores nothing.
- `shared/` — shared contracts/assets. `scripts/` — build/sign/package/notarize helpers.
- Many `*-draft.md` / `press-kit-draft` files in the tree are productization collateral, not app code.

## Build / release
- App: open `LessonLens/LessonLens.xcodeproj` in Xcode (or `xcodebuild`); deps via Swift Package Manager (`Package.resolved`).
- Signing / notarization / packaging: `scripts/sign-and-package.sh`, `scripts/notarize-pkg.sh`, `scripts/package.sh`, `scripts/configure-app.sh`. The `psd-sign` skill covers the Jamf/Installomator release path.

## Conventions & guardrails
- Public repo: never reintroduce hardcoded infrastructure identifiers or dev auth bypasses (both were deliberately removed before open-sourcing).
- The proxy/worker stores no user data; analysis runs through Gemini; transcription stays on-device. Keep it that way.
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
