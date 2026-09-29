/**
 * Settings src/index.ts reads at import time. Test files import this first,
 * because bun test shares one module registry across files and index.ts is
 * only evaluated once.
 */
if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
  process.env.JWT_SECRET = 'ci-test-secret-0123456789abcdef-0123456789abcdef';
}
process.env.GOOGLE_CLIENT_ID ||= 'ci-test-client.apps.googleusercontent.com';
process.env.VIDEO_BUCKET ||= 'test-video-bucket';
