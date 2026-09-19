/**
 * Starter test suite for the Cloud Run backend (bun test).
 *
 * Exercises the real Hono app via its fetch handler — no mocks of the unit
 * under test, no network calls. Auth-protected routes are only tested for
 * their unauthenticated rejection path (everything past auth needs Google
 * OAuth + Gemini credentials, which do not belong in CI).
 */
import { describe, expect, test } from 'bun:test';

// src/index.ts validates JWT_SECRET at import time (min 32 chars).
if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
  process.env.JWT_SECRET = 'ci-test-secret-0123456789abcdef-0123456789abcdef';
}

const { default: server, checkRateLimit, getRateLimitStatus } = await import('../src/index');

describe('HTTP surface', () => {
  test('GET / returns the health payload', async () => {
    const res = await server.fetch(new Request('http://localhost/'));
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, string>;
    expect(body.name).toBe('LessonLens API');
    expect(body.status).toBe('healthy');
    expect(body.runtime).toBe('Cloud Run');
  });

  test('responses carry the security headers set by middleware', async () => {
    const res = await server.fetch(new Request('http://localhost/'));
    expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(res.headers.get('X-Frame-Options')).toBe('DENY');
  });

  test('unknown paths return a JSON 404 echoing the path', async () => {
    const res = await server.fetch(new Request('http://localhost/no-such-route'));
    expect(res.status).toBe(404);
    const body = (await res.json()) as Record<string, string>;
    expect(body.error).toBe('Not found');
    expect(body.path).toBe('/no-such-route');
  });

  test('protected route rejects requests without a bearer token', async () => {
    const res = await server.fetch(
      new Request('http://localhost/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      })
    );
    expect(res.status).toBe(401);
  });
});

describe('rate limiter', () => {
  test('allows up to the limit, then blocks', () => {
    const key = `test-limit-${Date.now()}`;
    const limit = 3;
    for (let i = 1; i <= limit; i++) {
      const r = checkRateLimit(key, limit);
      expect(r.allowed).toBe(true);
      expect(r.current).toBe(i);
    }
    const blocked = checkRateLimit(key, limit);
    expect(blocked.allowed).toBe(false);
    expect(blocked.current).toBe(limit);
    expect(blocked.resetIn).toBeGreaterThan(0);
  });

  test('status reflects consumed quota', () => {
    const key = `test-status-${Date.now()}`;
    const limit = 5;
    checkRateLimit(key, limit);
    checkRateLimit(key, limit);
    const status = getRateLimitStatus(key, limit);
    expect(status.used).toBe(2);
    expect(status.remaining).toBe(3);
    expect(status.limit).toBe(limit);
  });

  test('unused key reports a full quota', () => {
    const status = getRateLimitStatus(`never-used-${Date.now()}`, 7);
    expect(status.used).toBe(0);
    expect(status.remaining).toBe(7);
  });
});
