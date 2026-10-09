---
type: Module
title: Shared prompt module (shared/prompts)
description: Prompt builders for text analysis, video analysis and coaching chat that both backends import by relative path; covers template layout, the JSON response contract with the Swift app, the wait-time pause rule, and why the import paths must not move.
tags: [prompts, gemini, shared, typescript, coaching-tone]
openwiki:
  roles: [architecture, domain]
  change_kinds: [prompt, response-schema, public-api]
  source_paths:
    - shared/prompts/index.ts
    - shared/prompts/builder.ts
    - shared/prompts/types.ts
    - shared/prompts/templates/components.ts
    - shared/prompts/templates/text-analysis.ts
    - shared/prompts/templates/video-analysis.ts
    - shared/prompts/templates/chat.ts
  symbols: [buildAnalysisPrompt, buildVideoAnalysisPrompt, buildChatPrompt, processTemplate, TechniqueDefinition, PauseData, GeminiGenerateResponse]
  invariants:
    - Backends import from ../../../shared/prompts; the Dockerfile copies shared/ to keep that relative path valid.
    - Model output keys are camelCase (techniqueId, wasObserved); route handlers convert to snake_case for the app.
  validation_commands:
    - cd CloudRunBackend && bun test
---

# Shared prompt module

`shared/prompts` is the single place prompt wording lives. Edit **templates** to change what Gemini is asked; edit **builder.ts** only to change how pieces are assembled. It is consumed by the [Cloud Run API](cloud-run-api.md) (`routes/analyze.ts`, `analyze-video.ts`, `chat.ts`) and the [Cloudflare Worker](cloudflare-worker.md) (text + video routes).

## Public surface

`shared/prompts/index.ts` re-exports exactly: types (`TechniqueDefinition`, `PauseInfo`, `PauseData`, `TextAnalysisPromptOptions`, `VideoAnalysisPromptOptions`, `ChatPromptOptions`, `ChatMessage`, `GeminiGenerateResponse`) and `buildAnalysisPrompt`, `buildVideoAnalysisPrompt`, `buildChatPrompt`. A new builder or type is not reachable by routes until it is added to `index.ts`.

| Builder | Input | Output | Used by |
|---|---|---|---|
| `buildAnalysisPrompt` | transcript, techniques, `includeRatings`, optional `pauseData` | one prompt string | `POST /analyze` |
| `buildVideoAnalysisPrompt` | techniques, `includeRatings` | prompt string (video itself is a separate `fileData` part) | `POST /analyze/video` |
| `buildChatPrompt` | transcript, analysis + evaluation summaries, optional reflection summary, messages, technique names | `{systemPrompt, messages}` with role `assistant` mapped to Gemini's `model` | `POST /chat` |

## Assembly rules (`builder.ts`)

- `processTemplate` does `{{var}}` substitution via `String.replace` on a global regex per key.
- Text prompt order: `TEXT_ANALYSIS_SYSTEM` -> transcript section -> pause section (**only if** `pauseData` is present *and* a technique with `id === 'wait-time'` is selected) -> techniques header + each technique (name, ID, description, look-fors, exemplar phrases) -> response schema (with/without ratings) -> `RATING_SCALE` when ratings on -> guidelines.
- Watch out: no technique definition shipped in the app's `Frameworks/*.swift` currently has id `wait-time` (only unit-test fixtures and a comment mention it), so in the shipped build the pause section is never added to the analysis prompt; pauses still reach the model through the chat transcript markers. Re-check before promising "wait time analysis" behaviour.
- Video prompt: same minus transcript/pause, using `GUIDELINES_VIDEO_BASE` (asks for timestamps and non-verbal behaviours).
- Chat: `CHAT_SYSTEM_PROMPT` (technique names injected) + `CHAT_CONTEXT_SECTION`; the app-built `reflection_summary` string is appended verbatim (the exported `CHAT_REFLECTION_SECTION` template is imported but not used - the Swift `ChatService.buildReflectionSummary` already produces the heading text).

## Contract with the app

The JSON schema in `templates/components.ts` (`overallSummary`, `strengths`, `growthAreas`, `actionableNextSteps`, `techniqueEvaluations[{techniqueId, wasObserved, rating?, evidence, feedback, suggestions}]`) is parsed by the routes (they also strip a ```json fence) and re-keyed to snake_case for the Swift `AnalysisResponse` / `VideoAnalysisResponse` decoders (see [lesson workflow](../app/lesson-workflow.md)). Guidelines require using the exact technique `ID` as `techniqueId` - the app matches evaluations to techniques by that id (`TechniqueEvaluation.techniqueName` falls back to the id when unmatched). Techniques themselves come from the app's [frameworks and techniques](../app/frameworks-and-techniques.md); the backend treats them as opaque input (max 20).

## Product tone is a prompt requirement

Templates tell the model to use warm, factual language, avoid superlatives and exclamation points, and (chat) cite `[MM:SS]` timestamps, keep replies under ~300 words and use only light Markdown (the app's `MarkdownText` renders a limited subset). This is how the "coaching, not evaluation" rule from [architecture overview](../architecture/overview.md) is enforced on model output - keep it when editing.

## Change guidance

- Wording change: edit the template; no route change needed. Re-run `cd CloudRunBackend && bun test` (route tests use fake Gemini replies, so they do not validate wording - review the rendered prompt by calling the builder).
- Schema change (new field): update both `RESPONSE_SCHEMA_*`, the route mappers in `analyze.ts`/`analyze-video.ts` (and the worker equivalents), the Swift Codable response structs and the `Analysis`/`TechniqueEvaluation` SwiftData models (a SwiftData schema change can trigger the store reset described in [app overview](../app/overview.md)).
- Do not change the `../../../shared` import paths or Dockerfile `COPY shared` lines without updating both: `CloudRunBackend/Dockerfile` puts `shared/` at `/app/shared` and the app at `/app/CloudRunBackend`; the root `Dockerfile` uses the same layout (see [deployment](../operations/deployment-and-release.md)).
- Legacy duplicate: `AnalysisService.buildAnalysisPrompt` in the Swift app is an older client-side prompt copy not used by the request path (the app posts raw transcript + techniques); do not treat it as canonical.
