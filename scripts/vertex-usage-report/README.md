# Vertex AI usage report

A Google Apps Script that reports LessonLens's Gemini usage on Vertex AI: requests, errors by response code, and input/output tokens per model for the last 7 days, the last 30 days, and since July 1. It also links to the Cloud Billing cost report for the LessonLens project, grouped by SKU.

It reads project-wide totals from Cloud Monitoring (`aiplatform.googleapis.com/publisher/online_serving/*`) as the person who runs it. No per-teacher or per-request data is read.

## Setup

The district blocks clasp sign-in (`admin_policy_enforced`), so set it up in the Apps Script editor:

1. At script.google.com, create a new project and paste `Code.gs` over the default file. In Project Settings, tick **Show "appsscript.json" manifest file in editor**, then replace that file's contents with `appsscript.json`.
2. In Project Settings > Script Properties, add:
   - `GCP_PROJECT`: the Cloud project that runs the LessonLens backend
   - `BILLING_ACCOUNT`: its billing account ID (for the cost link only)
   - `REPORT_TO`: who gets the weekly email (comma-separated for more than one)

   These stay out of the repo, which is public.
3. Run `previewReport` and approve the permissions it asks for (read Cloud Monitoring, call external URLs, send email as you, manage the script's triggers). The report appears in the execution log.
4. Run `sendWeeklyReport` once to check the email arrives.
5. Run `installWeeklyTrigger` once. It schedules `sendWeeklyReport` for Mondays between 7 and 8 AM Pacific; running it again replaces the schedule rather than adding a second one. If a scheduled run fails, Apps Script emails the script's owner.

The report runs as the person who set it up. If that account loses access, the weekly email stops.

The person running it needs Monitoring Viewer and `serviceusage.services.use` on the project (the script bills its Monitoring calls to that project), and Billing Account Viewer on the billing account (for the cost link to open).

After changing `Code.gs` in the repo, paste it into the editor again.

## Tests

```bash
bun test scripts/vertex-usage-report
```

The tests cover the report logic in `Code.gs` (windows, totals, error grouping, paging, formatting), the Monitoring request headers, the weekly email, and the trigger setup, with sample data and stand-ins for the Apps Script services. CI does not run them.

## Notes

- LessonLens moved to Vertex AI on 2026-09-28. Earlier usage ran on a retired AI Studio key and is not in these metrics, so "since July 1" starts there in practice.
