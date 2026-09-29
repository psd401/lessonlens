# Releasing LessonLens

Releases are built, signed, notarized and packaged with the `psd-sign` skill,
then published as a GitHub Release. PSD IT's AutoPkg recipe picks up
`/releases/latest` and deploys it through Jamf.

## Fixed values

- **pkg identifier:** `net.psd401.lessonlens` (keep it; the installed-version
  check and the Mac's receipt key on it)
- **Tag / version:** `v<MARKETING_VERSION>`, digits and dots only
- **Asset:** one `.pkg`, no drafts or prereleases

## Before archiving

1. `LessonLens/Config/Local.xcconfig` must exist on the build Mac (git-ignored;
   `scripts/configure-app.sh` writes it). The district config is baked into
   the app's Info.plist at build time, so no Jamf configuration profile is
   needed. `psd-sign` runs `scripts/check-app-config.sh` on the archived app
   and stops if a value is empty.
2. Bump `MARKETING_VERSION` for the LessonLens target (Debug and Release) in a
   merged PR. The build must be of `origin/main`.
3. At release, update `docs/help/help-steps.js` (`appVersion`, `updated`,
   anything the release changed) and `docs/history/history.js`.

## Signing and the app sandbox

- Release builds use `LessonLens/Resources/LessonLens-Release.entitlements`
  with the hardened runtime. `LessonLens/expected-entitlements.txt` lists what
  the signed app must carry; `psd-sign` checks it.
- **Release is not sandboxed, on purpose.** Every release through v1.1.1 was
  shipped with no entitlements at all (an older signing step removed them), so
  teachers' data lives outside the sandbox container:
  `~/Library/Application Support/default.store` and
  `~/Library/Application Support/com.peninsula.lessonlens/Recordings`.
  A sandboxed release would look in `~/Library/Containers/…` instead and the
  existing sessions would appear to vanish. Adopting the sandbox needs a
  container-migration plan and testing on a copy of real data first.
- Debug builds keep the sandboxed `LessonLens.entitlements`.

## Released

- **v1.1.1** — last release before this file. Shipped with no entitlements
  (see above); the microphone entitlement was also missing, so live
  recording under the hardened runtime may not have worked.
