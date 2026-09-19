# LessonLens

Privacy-first AI lesson-coaching tool for Peninsula SD teachers. Teachers
record a lesson; on-device transcription + Gemini analysis give private
feedback. Nothing is stored server-side.

## Repo map

| Path | What it is |
|------|------------|
| `LessonLens/` | Swift app (Xcode project + `Package.swift`) — the client |
| `CloudRunBackend/` | Bun + Hono API deployed to Cloud Run (current backend) |
| `CloudflareWorker/` | Bun + Hono API on Cloudflare Workers (alternate deploy) |
| `shared/prompts/` | Prompt builders imported by both backends via relative path |
| `docs/` | Terms/privacy, design docs |

## Commands (verified)

```bash
# Backends (bun only — never npm/npx)
cd CloudRunBackend  && bun install --frozen-lockfile && bun run build && bun test
cd CloudflareWorker && bun install --frozen-lockfile && bun test

# Swift app: open LessonLens/LessonLens.xcodeproj in Xcode (macOS only; not in CI)
```

## Stack

- Backends: Bun runtime, Hono, jose (JWT), Google Gemini API upstream
- Auth: Google OAuth (`@psd401.net` domain), short-lived JWT sessions
- CI: `.github/workflows/psd-ci.yml` calls the org reusable gate once per
  backend directory; Swift app is a TODO (needs macOS runner)

## Anti-patterns

- **Never weaken CI**: don't remove/skip tests, loosen gates, or add
  `allow-no-tests` to the backend jobs.
- Don't store user content server-side — statelessness is a privacy promise
  made in README/terms, not an implementation detail.
- Don't touch `shared/prompts` import paths; the Dockerfile copies `shared/`
  to preserve the `../../../shared` relative imports.
- JWT_SECRET must stay >= 32 chars; `src/index.ts` enforces it at startup.
- Rate limiting is in-memory by design (see comments in
  `CloudRunBackend/src/index.ts`) — don't "fix" it without reading them.
