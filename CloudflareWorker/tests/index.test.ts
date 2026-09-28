/**
 * Starter test suite for the Cloudflare Worker (bun test).
 *
 * Calls the real Hono app's fetch handler directly — no wrangler, no
 * network. Routes that need KV/Gemini/Google credentials are only tested
 * for their unauthenticated rejection path.
 */
import { describe, expect, test } from 'bun:test';
import app from '../src/index';

// Minimal Bindings stub: the health/404 paths never touch these, and the
// auth middleware rejects before any KV or upstream call is made.
const env = {
  GOOGLE_CLIENT_ID: 'test-client-id',
  JWT_SECRET: 'ci-test-secret-0123456789abcdef-0123456789abcdef',
  ALLOWED_DOMAIN: 'psd401.net',
  RATE_LIMIT_PER_HOUR: '20',
  RATE_LIMIT: {} as unknown,
  GEMINI_API_KEY: 'test-key',
  GEMINI_TEXT_MODEL: 'test-model',
  GEMINI_VIDEO_MODEL: 'test-model',
  VIDEO_RATE_LIMIT_PER_HOUR: '5',
};

describe('worker HTTP surface', () => {
  test('GET / returns the health payload', async () => {
    const res = await app.request('/', {}, env);
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, string>;
    expect(body.name).toBe('LessonLens API');
    expect(body.status).toBe('healthy');
  });

  test('responses carry the security headers set by middleware', async () => {
    const res = await app.request('/', {}, env);
    expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(res.headers.get('X-Frame-Options')).toBe('DENY');
  });

  test('unknown paths return 404', async () => {
    const res = await app.request('/no-such-route', {}, env);
    expect(res.status).toBe(404);
  });

  test('protected route rejects requests without a bearer token', async () => {
    const res = await app.request(
      '/analyze',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      },
      env
    );
    expect(res.status).toBe(401);
  });
});
