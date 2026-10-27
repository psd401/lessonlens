# Vertex AI usage report

A Google Apps Script that reports LessonLens's Gemini usage on Vertex AI: requests, errors by response code, and input/output tokens per model for the last 7 days, the last 30 days, and since July 1. It also links to the Cloud Billing cost report for the LessonLens project, grouped by SKU.

It reads project-wide totals from Cloud Monitoring (`aiplatform.googleapis.com/publisher/online_serving/*`) as the person who runs it. No per-teacher or per-request data is read.

## Setup

1. Create the Apps Script project and push these files with [clasp](https://github.com/google/clasp):
   ```bash
   cd scripts/vertex-usage-report
   bunx @google/clasp login
   bunx @google/clasp create --type standalone --title "LessonLens Vertex usage report" --rootDir .
   bunx @google/clasp push
   ```
   `clasp create` writes `.clasp.json` with the script's ID. It is git-ignored; keep it local.
2. In the Apps Script editor, open Project Settings > Script Properties and add:
   - `GCP_PROJECT`: the Cloud project that runs the LessonLens backend
   - `BILLING_ACCOUNT`: its billing account ID (for the cost link only)

   These stay out of the repo, which is public.
3. Run `previewReport` and approve the permissions it asks for (read Cloud Monitoring, call external URLs). The report appears in the execution log.

The person running it needs Monitoring Viewer on the project and Billing Account Viewer on the billing account (for the cost link to open).

## Tests

```bash
bun test scripts/vertex-usage-report
```

The tests cover the report logic in `Code.gs` (windows, totals, error grouping, paging, formatting) with sample data. CI does not run them.

## Notes

- LessonLens moved to Vertex AI on 2026-09-28. Earlier usage ran on a retired AI Studio key and is not in these metrics, so "since July 1" starts there in practice.
