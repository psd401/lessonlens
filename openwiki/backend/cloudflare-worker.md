---
type: Removed Component
title: Cloudflare Worker (removed alternative proxy)
description: Record of the former Cloudflare Workers variant of the LessonLens API that is no longer in the repository - what it was, why the Cloud Run backend is now the only backend, and what to check before reintroducing any Cloudflare path.
tags: [backend, cloudflare, workers, legacy, removed]
openwiki:
  roles: [architecture, repository]
  change_kinds: [removal, config]
  invariants:
    - No CloudflareWorker/ directory exists at the repository root; the Cloud Run backend (CloudRunBackend/) is the only backend implementation.
    - CI runs only the psd-ci-cloudrun-backend job; there is no Cloudflare job.
---

# Cloudflare Worker (removed)

The repository used to contain a second, smaller implementation of the LessonLens API for Cloudflare Workers (`CloudflareWorker/`, Bun + Hono, KV-backed rate limits). It is no longer present: there is no `CloudflareWorker/` directory at the repository root, the CI gate in `.github/workflows/psd-ci-jobs.yml` runs only `psd-ci-cloudrun-backend`, and the root README no longer mentions it. Treat the [Cloud Run API](cloud-run-api.md) as the only backend.

## What it used to differ on

The worker was a lower-capability mirror of the Cloud Run service. Its differences from the Cloud Run backend, as recorded before removal, matter only if it is brought back:

- Config came from `wrangler.toml` bindings rather than `process.env`, with no startup check on `JWT_SECRET` length.
- Rate limits were stored in a KV namespace instead of the in-process `Map` used by [Cloud Run API](cloud-run-api.md).
- Gemini was reached only through an API key; there was no Vertex path and no chat route.
- Video used the Gemini Files API, a path that the Cloud Storage pipeline in [video analysis pipeline](video-analysis-pipeline.md) has since replaced.

## If someone proposes restoring it

- A Cloudflare deployment would need its own copy of the auth, domain-lock, and ownership checks that live in `CloudRunBackend/src/routes/`. Security fixes do not carry over automatically.
- The shared prompt builders in [shared prompts](shared-prompts.md) were imported by the worker via `../../../shared`; restoring it would also require the same relative layout.
- Do not reintroduce the worker's CI job or deploy steps without restoring them in [build, test and CI](../operations/build-test-ci.md) and [deployment and release](../operations/deployment-and-release.md).
