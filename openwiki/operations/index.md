# Files

- [Build, test and CI commands](build-test-ci.md) - Verified commands for building and testing the Cloud Run backend and the macOS app, what CI does and does not cover (only the backend gate), dependency-pin warnings, and which checks are conditional.
- [Deployment, release and public docs](deployment-and-release.md) - How the backend is containerised and deployed to Cloud Run, how district deployments are bootstrapped with the setup scripts, how the signed macOS pkg release is produced, and how the GitHub Pages help/history sites are kept current.
- [Vertex AI usage report (Apps Script)](vertex-usage-report.md) - The operator-run Google Apps Script that reports LessonLens Gemini request, error and token totals on Vertex AI from Cloud Monitoring for 7-day, 30-day and since-July-1 windows, with a billing cost link - how it is set up, how report.test.ts pins its logic, and what it deliberately does not read.
