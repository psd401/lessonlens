---
type: Runbook
title: Vertex AI usage report (Apps Script)
description: The operator-run Google Apps Script that reports LessonLens Gemini request, error and token totals on Vertex AI from Cloud Monitoring for 7-day, 30-day and since-July-1 windows, with a billing cost link - how it is set up, how report.test.ts pins its logic, and what it deliberately does not read.
tags: [operations, vertex-ai, gemini, monitoring, cost, apps-script, usage-report]
openwiki:
  roles: [operations, testing]
  change_kinds: [reporting, monitoring]
  source_paths:
    - scripts/vertex-usage-report/Code.gs
    - scripts/vertex-usage-report/README.md
    - scripts/vertex-usage-report/appsscript.json
  symbols: [previewReport, buildReport, reportWindows, fetchSeries, fetchJson_, sumPoints, summarize, formatErrors, billingReportUrl, renderText, renderHtml]
  test_paths:
    - scripts/vertex-usage-report/report.test.ts
  invariants:
    - Only project-wide aggregate counts are read from Cloud Monitoring; no per-teacher or per-request data.
    - Any HTTP response code outside 2xx counts as an error, and error codes are grouped by code.
    - Each window is a single aligned point covering its full duration (alignment period equals the window length, at least 60 seconds).
    - The billing link is included only when the BILLING_ACCOUNT script property is set.
    - previewReport throws when GCP_PROJECT is not set.
  validation_commands:
    - bun test scripts/vertex-usage-report
---

# Vertex AI usage report (Apps Script)

`scripts/vertex-usage-report/` is a small Google Apps Script (`Code.gs`) that summarizes how much LessonLens uses Gemini on Vertex AI. It is an operator tool: the person who runs it reads project-wide totals, so it can answer "how many requests and tokens, and how many failed" without touching the backend or any teacher data. It is not part of the backend runtime, is not deployed by [setup.sh](deployment-and-release.md#district-bootstrap-scripts) or Cloud Build, and is not run by CI.

**Consult this page when** changing what the usage report counts, adding a window or metric, or setting up the script for a new Cloud project.

## Why it exists and what it reads

The backend sends every Gemini call to Vertex AI through `createGeminiClient` in `CloudRunBackend/src/gemini-client.ts` (see [Cloud Run API](../backend/cloud-run-api.md#gemini-client-gemini-clientts-gcp-authts)). Google records those calls in Cloud Monitoring under `aiplatform.googleapis.com/publisher/online_serving/*`. The report reads two of those metrics for the Cloud project that runs the backend:

- `model_invocation_count`, grouped by `resource.label.model_user_id` (model) and `metric.label.response_code`.
- `token_count`, grouped by model and `metric.label.type`. Only `input` and `output` are counted; other token types are ignored.

The file header records that LessonLens moved to Vertex AI on 2026-09-28, so usage before that date (on the retired AI Studio key) is not in these metrics. The design reads only aggregates, which fits the rule that the backend stores no user data (see the [architecture overview](../architecture/overview.md)).

## Flow

<!-- openwiki: mermaid parse failed and this diagram was converted to a text fence so it does not break rendering. Fix the diagram source and restore the mermaid fence. Parser error: Heuristic: a semicolon inside a label breaks rendering; rephrase the label. -->
```text
flowchart TD
    A["previewReport() run from the Apps Script editor"] --> B["getConfig_ reads GCP_PROJECT and BILLING_ACCOUNT"]
    B --> C["buildReport(config, now)"]
    C --> D["reportWindows: last 7 days, last 30 days, since July 1"]
    D --> E["fetchSeries model_invocation_count per window"]
    D --> F["fetchSeries token_count per window"]
    E --> G["summarize per-model requests, errors, errorsByCode, tokens"]
    F --> G
    G --> H["renderText and renderHtml"]
    H --> I["previewReport logs the text; html is returned but no code path sends it"]
```

Caption: the only entry point in `Code.gs` is `previewReport`, which logs the plain-text report to the execution log. `buildReport` returns both `text` and `html`, but nothing in the repository consumes the HTML (no scheduled trigger or mail function exists in `Code.gs`). Adding delivery is a new feature, not a fix.

## Responsibilities

| Symbol | Owns |
|---|---|
| `previewReport` | Entry point for the editor; logs `buildReport(...).text`. |
| `getConfig_` | Reads `GCP_PROJECT` (required, throws otherwise) and `BILLING_ACCOUNT` (optional) from Script Properties. Both stay out of the public repo. |
| `reportWindows(now)` | Three windows. "Since July 1" uses July of the current year when `now` is July or later, otherwise July of the previous year (school year to date). |
| `fetchSeries(project, metric, groupBy, start, end, fetchFn?)` | Builds the Monitoring `timeSeries` query (`ALIGN_SUM`, `REDUCE_SUM`, one alignment period equal to the window length, minimum 60 s) and follows `nextPageToken`. `fetchFn` is injected by tests. |
| `fetchJson_` | The only code that calls `UrlFetchApp` and `ScriptApp.getOAuthToken()`; throws on any non-200 response. |
| `sumPoints` | Adds `int64Value` across a series' points. |
| `summarize(invocations, tokens)` | Per-model totals. Non-2xx codes (`/^2\d\d$/` does not match) add to `errors` and `errorsByCode`. A missing model label becomes `unknown`. |
| `formatErrors`, `formatNumber`, `formatDate` | Presentation. Dates use the script's local day (`appsscript.json` sets `America/Los_Angeles`), not UTC. |
| `billingReportUrl` | Cloud Billing cost report grouped by SKU, scoped to one project. |
| `renderText`, `renderHtml` | Output; HTML escapes model names and labels. |

The file ends with a `module.exports` guard so Bun tests can load the pure functions; Apps Script has no `module`, so the guard is inert there.

## Setup and running

From the README:

1. Create the Apps Script project and push these files with `clasp` from `scripts/vertex-usage-report`. `clasp create` writes a `.clasp.json` that the README says is git-ignored and stays local.
2. In Project Settings > Script Properties, set `GCP_PROJECT` and `BILLING_ACCOUNT`.
3. Run `previewReport` and approve the scopes in `appsscript.json` (`monitoring.read`, `script.external_request`). The report appears in the execution log.

The person running it needs Monitoring Viewer on the project and Billing Account Viewer on the billing account (for the cost link to open).

## Tests and validation

`scripts/vertex-usage-report/report.test.ts` loads `Code.gs` into a `vm` sandbox with a `module` object, so the tests run against the real file. Validation: `bun test scripts/vertex-usage-report` from the repository root. CI does not run this suite; run it when you change this folder.

Behavior matrix, by `describe` block:

- `reportWindows`: window starts are exactly 7 and 30 days before `now`; "since July 1" is this year's July after June and last year's before it (`since July 1 uses this year after July`, `since July 1 uses last year before July`).
- `summarize`: non-2xx counts as errors and totals sum all points (`counts non-2xx codes as errors and sums all points`); models stay separate and non-input/output token types are ignored (`keeps models apart and ignores other token types`); no series means no models.
- `formatErrors`: `shows count, rate and codes` and `zero errors is just 0`.
- `formatting`: `numbers get thousands separators` and `dates use the local day, not UTC`.
- `fetchSeries`: `sends the aggregation query and follows pages` checks the filter, alignment period, group-by fields and `pageToken` on the second request.
- `buildReport`: `reports each window and the billing link`; `a window with no traffic says so and skips the link without an account`; `escapes model names in HTML`.

## Change recipes

- **Add a metric or window.** Extend `reportWindows` or add a `fetchSeries` call in `buildReport`, then update `summarize` and the renderers. Add a case to `report.test.ts` that fixes the new window boundary or series shape, and keep `formatErrors`' 2xx rule unchanged unless the error definition changes deliberately.
- **Change error classification.** Edit the `/^2\d\d$/` check in `summarize` and the matching test `counts non-2xx codes as errors and sums all points`.
- **Add email or scheduled delivery.** Not present today. It would need a trigger and a consumer for `html`; it would also need a review of what the recipient is allowed to see, since the report is aggregate-only by design.

Scope boundaries: this page covers only the Apps Script. Gemini behavior, Vertex location and the metrics' source are in [Cloud Run API](../backend/cloud-run-api.md); deploying the backend is in [deployment and release](deployment-and-release.md).

Fixture rule: the test file uses 8-digit numbers to avoid the 7-digit student-number pattern that the secret scan flags (see the guardrails in [deployment and release](deployment-and-release.md#guardrails)).
