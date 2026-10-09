---
type: Service
title: Cloudflare Worker (alternative proxy)
description: The stateless Cloudflare Workers variant of the LessonLens API - which routes it implements, how it differs from the Cloud Run backend (KV rate limits, API-key Gemini only, no chat, no Vertex/Cloud Storage), and when it is safe to ignore.
tags: [backend, cloudflare, workers, hono, kv, legacy]
openwiki:
  roles: [architecture, integration]
  change_kinds: [api-route, config]
  source_paths:
    - CloudflareWorker/src/index.ts
    - CloudflareWorker/src/routes/auth.ts
    - CloudflareWorker/src/routes/analyze.ts
    - CloudflareWorker/src/routes/analyze-video.ts
    - CloudflareWorker/src/routes/upload.ts
    - CloudflareWorker/wrangler.toml
  symbols: [Env, analyzeRoutes, analyzeVideoRoutes, uploadRoutes, authRoutes]
  test_paths:
    - CloudflareWorker/tests/index.test.ts
  validation_commands:
    - cd CloudflareWorker && bun test
---

# Cloudflare Worker

A second, smaller implementation of the same API that runs on Cloudflare Workers (`wrangler.toml`, name `lessonlens-api`). The README lists it as the "Alternative backend"; the app's production path in this repo is the [Cloud Run API](cloud-run-api.md). `CLAUDE.md` describes it as a Bun + Hono stateless proxy that stores nothing. Treat the Cloud Run service as the reference implementation and consult this page only if the worker is being deployed or kept in sync.

## What it implements

`src/index.ts` mounts `/auth`, `/analyze`, `/analyze/video`, `/upload` on a `Hono<{Bindings: Env}>` app and exports the app as the worker (tests call `app.request('/', {}, env)`). Same CORS/security-header/404/500 behaviour as Cloud Run. Prompts come from the same [shared prompt module](shared-prompts.md) via `../../../shared/prompts`.

## Differences from Cloud Run

| Aspect | Cloud Run | Worker |
|---|---|---|
| Config source | `process.env`, validated at startup | `Env` bindings from `wrangler.toml` `[vars]` + secrets (`GEMINI_API_KEY`, `GOOGLE_CLIENT_ID`, `JWT_SECRET`); no startup check of secret length |
| Rate limit | in-memory `Map`, counted at check time | KV namespace `RATE_LIMIT` (id left blank in repo), hourly key `rate:<user>:<ISO hour>`, incremented **after** a successful Gemini result with `expirationTtl: 3600` |
| Gemini access | API key or Vertex (`GEMINI_BACKEND`) | API key only, direct `fetch` (`maxOutputTokens: 4096` for text) |
| Video | Cloud Storage + Vertex, plus legacy Files API with ownership checks | Files API only (`geminiFileName`), 5-minute processing timeout; no `userHash` ownership checks |
| Chat | `POST /chat` | not implemented |
| Error logging | `describeGeminiError` (no body) | `analyze.ts` logs the Gemini error body text on failure |

Consequences for changes: a new Cloud Run feature is **not** automatically available in the worker, and the current app's video flow (`/upload/initiate/gcs`, `/chat`) will not work against it. Security fixes to shared logic (domain lock, ownership checks, error-body logging) would need to be ported by hand.

## Config and deploy

`wrangler.toml` sets `ALLOWED_DOMAIN`, `RATE_LIMIT_PER_HOUR`, `GEMINI_TEXT_MODEL`, `GEMINI_VIDEO_MODEL`, `VIDEO_RATE_LIMIT_PER_HOUR`; secrets are set with `wrangler secret`. Scripts in `package.json`: `dev` (`wrangler dev`), `deploy`, `tail`, `test` (`bun test`). Do not commit the KV namespace id.

## Validation

`cd CloudflareWorker && bun test` - `tests/index.test.ts` > `worker HTTP surface` covers health, security headers and 404 with a stubbed `Env`; auth-protected paths are only tested for unauthenticated rejection. CI runs this directory as its own job (see [build, test and CI](../operations/build-test-ci.md)).
