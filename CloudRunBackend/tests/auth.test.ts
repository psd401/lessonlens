/**
 * Session token rules (review findings SEC-02 and SEC-03): access and refresh
 * tokens can't stand in for each other, every token needs a subject, and a
 * chain of refreshes ends MAX_SESSION_DAYS after the last Google sign-in.
 * Tokens are signed in-test with the test JWT_SECRET; no Google calls.
 */
import { describe, expect, test } from 'bun:test';
import './test-env';
import * as jose from 'jose';

const { default: server, env } = await import('../src/index');
const { issueTokens, verifySession } = await import('../src/routes/auth');

const DAY = 24 * 60 * 60;
const nowSeconds = () => Math.floor(Date.now() / 1000);
const secret = () => new TextEncoder().encode(process.env.JWT_SECRET);

/** Signs a token with explicit claims and lifetime, for cases issueTokens can't produce. */
async function sign(claims: jose.JWTPayload, { sub = 'teacher-1', iat = nowSeconds(), lifetime = 7 * DAY } = {}) {
  const jwt = new jose.SignJWT(claims).setProtectedHeader({ alg: 'HS256' }).setIssuedAt(iat).setExpirationTime(iat + lifetime);
  if (sub) jwt.setSubject(sub);
  return jwt.sign(secret());
}

async function refresh(token: string): Promise<Response> {
  return server.fetch(
    new Request('http://localhost/auth/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: token }),
    })
  );
}

async function analyzeStatus(token: string): Promise<number> {
  const res = await server.fetch(
    new Request('http://localhost/analyze', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({}),
    })
  );
  return res.status;
}

describe('verifySession', () => {
  test('accepts an issued access token', async () => {
    const { access_token } = await issueTokens('teacher-1', nowSeconds());
    expect(await verifySession(`Bearer ${access_token}`)).toEqual({ valid: true, userId: 'teacher-1' });
  });

  test('rejects a refresh token used as an access token', async () => {
    const { refresh_token } = await issueTokens('teacher-1', nowSeconds());
    expect((await verifySession(`Bearer ${refresh_token}`)).valid).toBe(false);
  });

  test('rejects a token with no subject', async () => {
    const token = await sign({ token_type: 'access' }, { sub: '' });
    expect((await verifySession(`Bearer ${token}`)).valid).toBe(false);
  });

  test('rejects an unknown token type', async () => {
    const token = await sign({ token_type: 'admin' });
    expect((await verifySession(`Bearer ${token}`)).valid).toBe(false);
  });

  test('accepts an untyped 7-day access token from before token types', async () => {
    const token = await sign({ user: { id: 'teacher-1' } }, { lifetime: 7 * DAY });
    expect(await verifySession(`Bearer ${token}`)).toEqual({ valid: true, userId: 'teacher-1' });
  });

  test('rejects an untyped 30-day refresh token from before token types', async () => {
    const token = await sign({ userId: 'teacher-1' }, { lifetime: 30 * DAY });
    expect((await verifySession(`Bearer ${token}`)).valid).toBe(false);
  });

  test('protected routes reject a refresh token', async () => {
    const { refresh_token } = await issueTokens('teacher-1', nowSeconds());
    expect(await analyzeStatus(refresh_token)).toBe(401);
  });
});

describe('POST /auth/refresh', () => {
  test('issues a working pair and keeps auth_time unchanged', async () => {
    const authTime = nowSeconds() - 5 * DAY;
    const { refresh_token } = await issueTokens('teacher-1', authTime);

    const res = await refresh(refresh_token);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { access_token: string; refresh_token: string; expires_in: number };
    expect(body.expires_in).toBe(7 * DAY);
    expect(await verifySession(`Bearer ${body.access_token}`)).toEqual({ valid: true, userId: 'teacher-1' });

    const next = jose.decodeJwt(body.refresh_token);
    expect(next.token_type).toBe('refresh');
    expect(next.auth_time).toBe(authTime);
    expect(next.sub).toBe('teacher-1');
  });

  test('rejects an access token', async () => {
    const { access_token } = await issueTokens('teacher-1', nowSeconds());
    expect((await refresh(access_token)).status).toBe(401);
  });

  test('rejects a refresh token past the session cap', async () => {
    const authTime = nowSeconds() - (env.MAX_SESSION_DAYS + 1) * DAY;
    const { refresh_token } = await issueTokens('teacher-1', authTime);
    expect((await refresh(refresh_token)).status).toBe(401);
  });

  test('rejects a typed refresh token with no auth_time', async () => {
    const token = await sign({ token_type: 'refresh' }, { lifetime: 30 * DAY });
    expect((await refresh(token)).status).toBe(401);
  });

  test('rejects a refresh token with no subject', async () => {
    const token = await sign({ token_type: 'refresh', auth_time: nowSeconds() }, { sub: '', lifetime: 30 * DAY });
    expect((await refresh(token)).status).toBe(401);
  });

  test('rejects an untyped 30-day refresh token from before token types', async () => {
    const token = await sign({ userId: 'teacher-1' }, { lifetime: 30 * DAY });
    expect((await refresh(token)).status).toBe(401);
  });

  test('rejects an untyped 7-day access token', async () => {
    const token = await sign({ user: { id: 'teacher-1' } }, { lifetime: 7 * DAY });
    expect((await refresh(token)).status).toBe(401);
  });

  test('rejects a token signed with another secret', async () => {
    const token = await new jose.SignJWT({ token_type: 'refresh', auth_time: nowSeconds() })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject('teacher-1')
      .setIssuedAt()
      .setExpirationTime('30d')
      .sign(new TextEncoder().encode('a-different-secret-0123456789abcdef-0123'));
    expect((await refresh(token)).status).toBe(401);
  });
});

describe('MAX_SESSION_DAYS startup validation', () => {
  test('refuses to start with a non-numeric MAX_SESSION_DAYS', () => {
    const result = Bun.spawnSync(['bun', '-e', "await import('./src/index.ts')"], {
      cwd: `${import.meta.dir}/..`,
      env: { ...process.env, MAX_SESSION_DAYS: 'thirty' },
    });
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr.toString()).toContain('MAX_SESSION_DAYS must be');
  });
});
