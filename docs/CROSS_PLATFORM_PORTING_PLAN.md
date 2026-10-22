# LessonLens: Cross-Platform Porting Plan

**Goal:** Run LessonLens beyond Apple Silicon Macs (Windows, and ideally any device) while preserving the privacy-preserving design, even where implementations must change.

**Status:** Planning document. Effort levels are relative (Low / Medium / High), not time estimates.

---

## 1. Decision: Windows-only vs. Device-Agnostic

### 1.1 The deciding fact

The current app is a **100% native macOS app** (SwiftUI + Swift + SwiftData + Apple system frameworks). Source: architecture review of `LessonLens/LessonLens/` (e.g. `App/LessonLensApp.swift`, `Features/`, `Core/Services/`).

The backend is already portable:

- `CloudRunBackend/` (Hono + Bun + TypeScript) has zero macOS dependencies.
- A `CloudflareWorker/` variant already exists.
- Shared Gemini prompts live in `shared/prompts/`.

Because the entire SwiftUI front end has to be rewritten **no matter which target we pick**, the front-end rewrite is a sunk cost in both scenarios. The only real question is *what shell we rewrite it into*.

### 1.2 Why device-agnostic is the smaller lift

| | Windows-native (WinUI / .NET MAUI) | Device-agnostic (one cross-platform shell) |
|---|---|---|
| Front-end rewrite | Required (Windows only) | Required (covers Win + Mac + Linux) |
| Future Mac/Linux support | Second rewrite later | Already included |
| Reuse of existing Mac users | None (we'd run two apps) | One codebase replaces the Swift app over time |
| Backend changes | Same | Same |

A Windows-native rewrite costs roughly the same as a cross-platform shell but only buys one platform. Building the front end **once** in a cross-platform framework is therefore the smaller *total* lift and the lower long-term maintenance burden.

### 1.3 Recommendation

**Build a single cross-platform desktop app.** Primary recommendation: **Tauri** (Rust shell + web UI). Fallback: **Electron** if the team prefers an all-JavaScript stack and accepts a larger bundle.

- Tauri: smaller bundle, lower memory, built-in OS keychain abstraction, no bundled Chromium. Steeper if the team has no Rust exposure, but app logic stays in TypeScript/JS.
- Electron: fastest for a JS/TS team, heaviest bundle (~bundled Chromium), mature tooling.

A pure web app (SaaS) is the *smallest* engineering lift but is rejected as the primary path because it forces audio/video to a server and breaks the local-only privacy posture (see Section 4). It is noted as a fallback only.

---

## 2. What Stays vs. What Changes

| Layer | Today (macOS) | Cross-platform target | Effort |
|---|---|---|---|
| Cloud backend | Cloud Run / Bun / Hono | **Unchanged** | None |
| Gemini prompts | `shared/prompts/` | **Unchanged** | None |
| UI | SwiftUI | React/Vue + TS in Tauri/Electron | High |
| Local DB | SwiftData | SQLite (cross-platform driver) | Medium |
| Credential storage | macOS Keychain (`KeychainService.swift`) | OS keyring abstraction | Medium |
| OAuth | `ASWebAuthenticationSession` | Cross-platform OAuth2 + system browser/PKCE | Medium |
| Audio capture | AVFoundation (`RecordingService.swift`) | Web Audio API / OS audio | Medium |
| Video import/extract | AVAssetExportSession | FFmpeg (bundled) | Medium |
| Transcription | WhisperKit (CoreML, Metal) | whisper.cpp **or** cloud (decision in §4) | Medium–High |
| PDF export | CoreGraphics (`ExportService.swift`) | JS PDF lib or server-side render | Medium |
| Packaging/signing | Jamf + notarization (`scripts/sign-and-package.sh`) | Authenticode + Intune/Company Portal (Win) | Medium |

---

## 3. Preserving the Privacy-Preserving Features

These are the design guarantees that must survive the port. Each is mapped to its cross-platform implementation.

### 3.1 Backend cannot see who used it or the content

- **Today:** Stateless backend; logs show API key usage, model, token count/cost only. No identity, no request/response content stored.
- **Port:** No change. The backend is reused as-is. Keep the stateless design and avoid adding any per-user logging in the new client.

### 3.2 Identity verification only, no usage tracking tied to identity

- **Today:** Google OAuth, domain-restricted to the district domain, identity used only to authorize.
- **Port:** Reimplement OAuth with a cross-platform library + PKCE, launching the system browser (Tauri/Electron both support this). Keep the same rule: identity authorizes access, it is not attached to usage telemetry.

### 3.3 Sensitive data stays on the device

- **Today:** SwiftData store + recordings in the user's app-support directory; tokens in Keychain.
- **Port:**
  - Local DB → SQLite file in the OS per-user app data directory (`%APPDATA%` on Windows, `~/.local/share` on Linux, `~/Library/Application Support` on Mac).
  - Tokens/secrets → OS credential store via a keyring abstraction (Tauri keyring, or `keytar`-style for Electron) backing onto Windows Credential Manager, Linux Secret Service, and macOS Keychain.
  - Keep recordings and transcripts local by default; nothing analysis-related is persisted server-side.

### 3.4 Ephemeral video handling

- **Today:** Videos go directly to the Gemini File API and are deleted after analysis; the backend stores nothing.
- **Port:** Unchanged (backend reuse). Verify the new client uses the same upload/delete flow in `CloudRunBackend/src/routes/`.

### 3.5 Voluntary, self-directed distribution (not an evaluation tool)

- **Today:** Mac Self-Service download; district can see who downloaded, not who uses it.
- **Port (Windows):** Distribute via Intune Company Portal or a district software center as an optional install. Same posture: download is visible to IT, active use is not. No auto-enrollment, no forced push.

---

## 4. The Transcription Decision (the one real privacy tradeoff)

You noted on-device transcription may have to be given up. Two viable paths; both are documented because the choice is a privacy decision, not just an engineering one.

### 4.1 Option A — Keep transcription on-device (privacy posture unchanged)

- Replace WhisperKit (CoreML/Metal) with **whisper.cpp**, which is cross-platform C++ and runs on Windows/Linux/Mac.
- Acceleration: CUDA (NVIDIA), Vulkan, or DirectML on Windows; CPU fallback everywhere.
- **Pros:** Audio never leaves the device. The strongest privacy claim is preserved verbatim.
- **Cons:** Higher integration effort; performance varies widely on typical district laptops without a capable GPU (CPU-only transcription is slow). Model files add bundle size.
- **Effort:** High.

### 4.2 Option B — Move transcription to the cloud (smaller lift, accept tradeoff)

- Add a transcription endpoint to the existing backend (e.g. a Whisper-family API or self-hosted model) that processes audio **ephemerally**.
- **Privacy controls required to keep the posture defensible:**
  - Process in memory, write nothing to disk server-side.
  - Do not persist audio or transcripts on the backend; return the transcript to the client, which stores it locally.
  - Do not attach identity to the transcription request (same as analysis calls today).
  - Document the change plainly: "audio is sent to our service for transcription and is not stored." Honesty about this matters more than hiding it.
- **Pros:** Lower client complexity, consistent performance regardless of device hardware.
- **Cons:** Audio leaves the device. This is a genuine reduction in the privacy guarantee and must be disclosed to teachers and the union.
- **Effort:** Medium.

### 4.3 Recommendation

- **Default to Option B** for the first cross-platform release (smaller lift, predictable on low-end hardware), with the ephemeral controls above as hard requirements.
- **Keep Option A on the roadmap** as the privacy-maximal mode, since whisper.cpp makes on-device transcription technically possible cross-platform. This lets you say on-device transcription was not abandoned for technical impossibility, only deferred for effort.

---

## 5. Component-by-Component Port Plan

### 5.1 Backend (Effort: None)

- Reuse `CloudRunBackend/` unchanged.
- If adding cloud transcription (§4.2), add one route mirroring the existing analyze/upload patterns and keep it stateless.

### 5.2 App shell (Effort: High)

- Scaffold Tauri (or Electron) project with React/Vue + TypeScript.
- Port the SwiftData model set (Recording, Transcript, Analysis, Technique, Reflection, ChatSession, ChatMessage, UserSettings) to SQLite tables/migrations.
- Re-create the feature views currently in `LessonLens/Features/`.

### 5.3 Authentication (Effort: Medium)

- Cross-platform OAuth2 + PKCE, system-browser based, domain-restricted.
- Store refresh/access tokens in the OS credential store via keyring abstraction.

### 5.4 Audio capture (Effort: Medium)

- Use the browser/WebView audio stack (Web Audio API / MediaRecorder) inside the shell, or an OS-level capture plugin.
- Output a format the transcription path accepts (WAV/M4A); use FFmpeg for conversion if needed.

### 5.5 Video import + audio extraction (Effort: Medium)

- Bundle FFmpeg for import validation, audio extraction, and format normalization (replaces AVAssetExportSession).
- Preserve current limits (size/duration) from app config.

### 5.6 Transcription (Effort: Medium or High, per §4)

- Implement chosen option. If Option A, integrate whisper.cpp with a CPU fallback and GPU acceleration where available.

### 5.7 Analysis + chat (Effort: Low)

- Thin HTTPS clients to the existing backend routes. Logic already lives server-side; the client just calls it.

### 5.8 PDF export (Effort: Medium)

- Replace CoreGraphics export with a JS PDF library in the client, or render server-side and return the file. Server-side keeps export consistent across OSes.

### 5.9 Packaging & distribution (Effort: Medium)

- **Windows:** Authenticode code-signing certificate; MSI/MSIX installer; distribute via Intune Company Portal as an optional app.
- **Mac (if continuing):** Tauri/Electron still notarize via existing scripts, adapted.
- **Linux (optional):** AppImage/deb/snap.

---

## 6. Recommended Sequencing

1. Stand up the Tauri/Electron shell with auth + local SQLite + a single working screen, talking to the existing backend.
2. Port analysis + chat (lowest effort, proves the backend reuse).
3. Add audio/video capture + import (FFmpeg).
4. Add transcription (Option B first).
5. Port PDF export and remaining feature views.
6. Windows packaging + Intune distribution; pilot with a small group.
7. (Roadmap) Add on-device transcription mode (Option A) and Mac/Linux builds from the same codebase.

---

## 7. Open Questions

1. Tauri vs. Electron — does the team have Rust comfort, or prefer all-JS?
2. Transcription: ship Option B (cloud) first, or hold for Option A (on-device) to keep the privacy claim intact at launch?
3. Is replacing the existing Swift Mac app with the cross-platform build acceptable, or must both run in parallel during transition?
4. Windows distribution channel confirmed as Intune/Company Portal? Any non-managed (BYOD) teacher devices to support?
5. Minimum Windows hardware spec for any on-device work (rules in/out Option A feasibility)?
6. Does the union messaging need to be updated if cloud transcription (Option B) is chosen?
