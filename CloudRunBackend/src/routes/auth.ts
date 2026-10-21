import { Hono } from 'hono';
import * as jose from 'jose';
import { env, type Env } from '../index';

export const authRoutes = new Hono();

// Google's public keys endpoint
const GOOGLE_CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

interface GoogleTokenPayload {
  iss: string;
  azp: string;
  aud: string;
  sub: string;
  hd?: string;  // Hosted domain
  email: string;
  email_verified: boolean;
  name: string;
  picture?: string;
  given_name?: string;
  family_name?: string;
  iat: number;
  exp: number;
}

interface ValidateRequest {
  id_token: string;
}

const ACCESS_TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60;
const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

type TokenType = 'access' | 'refresh';

/**
 * Which kind of token this is. Tokens carry a token_type claim so a refresh
 * token can't be used as an access token or the reverse.
 *
 * Access tokens issued before token_type existed (October 2026) have none.
 * The app only re-authenticates when its own clock says a token expired, so
 * rejecting them outright would leave teachers seeing "Authentication failed"
 * for up to 7 days. An untyped token that lived 7 days or less is therefore
 * still accepted as an access token; every one expires within 7 days of the
 * deploy that added token_type, after which this fallback can be removed.
 * Untyped refresh tokens (30-day lifetime) are not accepted at all: the app
 * has never refreshed successfully (its AuthResponse requires a `user` the
 * refresh response doesn't send), so only a direct API caller could use one.
 */
export function tokenTypeOf(payload: jose.JWTPayload): TokenType | undefined {
  if (payload.token_type === 'access' || payload.token_type === 'refresh') {
    return payload.token_type;
  }
  if (payload.token_type !== undefined) return undefined;
  if (typeof payload.iat !== 'number' || typeof payload.exp !== 'number') return undefined;
  return payload.exp - payload.iat <= ACCESS_TOKEN_TTL_SECONDS ? 'access' : undefined;
}

/**
 * Signs an access + refresh token pair. auth_time is when the teacher last
 * signed in with Google; /auth/refresh carries it forward unchanged so a
 * session can't be extended past MAX_SESSION_DAYS without a fresh Google
 * sign-in, which re-checks the account's domain.
 */
export async function issueTokens(
  subject: string,
  authTime: number,
  accessClaims: jose.JWTPayload = {}
): Promise<{ access_token: string; refresh_token: string; expires_in: number }> {
  const secret = new TextEncoder().encode(env.JWT_SECRET);
  const now = Math.floor(Date.now() / 1000);

  const accessToken = await new jose.SignJWT({ ...accessClaims, token_type: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt(now)
    .setExpirationTime(now + ACCESS_TOKEN_TTL_SECONDS)
    .setSubject(subject)
    .sign(secret);

  const refreshToken = await new jose.SignJWT({ token_type: 'refresh', auth_time: authTime })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt(now)
    .setExpirationTime(now + REFRESH_TOKEN_TTL_SECONDS)
    .setSubject(subject)
    .sign(secret);

  return { access_token: accessToken, refresh_token: refreshToken, expires_in: ACCESS_TOKEN_TTL_SECONDS };
}

/**
 * POST /auth/validate
 * Validates a Google ID token and returns a session token
 */
authRoutes.post('/validate', async (c) => {
  try {
    const body = await c.req.json<ValidateRequest>();
    const { id_token } = body;

    if (!id_token) {
      return c.json({ error: 'Missing id_token' }, 400);
    }

    // Fetch Google's public keys
    const JWKS = jose.createRemoteJWKSet(new URL(GOOGLE_CERTS_URL));

    // Verify the token
    let payload: GoogleTokenPayload;
    try {
      const { payload: verifiedPayload } = await jose.jwtVerify(id_token, JWKS, {
        issuer: ['https://accounts.google.com', 'accounts.google.com'],
        audience: env.GOOGLE_CLIENT_ID,
      });
      payload = verifiedPayload as unknown as GoogleTokenPayload;
    } catch (err) {
      console.error('Token verification failed:', err);
      return c.json({ error: 'Invalid token' }, 401);
    }

    // CRITICAL: Verify the hosted domain (server-side domain restriction)
    // Defense-in-depth: check both hd claim AND email domain suffix
    const allowedDomain = env.ALLOWED_DOMAIN;
    const emailDomain = payload.email?.split('@')[1]?.toLowerCase();

    if (!payload.hd || payload.hd !== allowedDomain) {
      // Log rejection without exposing full email (privacy)
      console.warn(`Domain rejection: hd=${payload.hd}, expected=${allowedDomain}`);
      return c.json({
        error: 'Access denied',
        message: `Only @${allowedDomain} accounts are allowed`
      }, 403);
    }

    // Additional check: verify email domain matches (defense-in-depth)
    if (emailDomain !== allowedDomain) {
      console.warn(`Email domain mismatch: domain=${emailDomain}, expected=${allowedDomain}`);
      return c.json({
        error: 'Access denied',
        message: `Only @${allowedDomain} accounts are allowed`
      }, 403);
    }

    // Verify email is verified
    if (!payload.email_verified) {
      return c.json({ error: 'Email not verified' }, 403);
    }

    // Create user object
    const user = {
      id: payload.sub,
      email: payload.email,
      displayName: payload.name,
      photoURL: payload.picture || null,
    };

    const tokens = await issueTokens(user.id, Math.floor(Date.now() / 1000), { user });

    return c.json({ ...tokens, user });

  } catch (err) {
    console.error('Auth validation error:', err);
    return c.json({ error: 'Authentication failed' }, 500);
  }
});

/**
 * POST /auth/refresh
 * Refreshes an expired session token using a refresh token
 */
authRoutes.post('/refresh', async (c) => {
  try {
    const body = await c.req.json<{ refresh_token: string }>();
    const { refresh_token } = body;

    if (!refresh_token) {
      return c.json({ error: 'Missing refresh_token' }, 400);
    }

    const secret = new TextEncoder().encode(env.JWT_SECRET);
    let payload: jose.JWTPayload;

    try {
      ({ payload } = await jose.jwtVerify(refresh_token, secret));
    } catch (err) {
      return c.json({ error: 'Invalid or expired refresh token' }, 401);
    }

    const authTime = payload.auth_time;
    if (tokenTypeOf(payload) !== 'refresh' || !payload.sub || typeof authTime !== 'number') {
      return c.json({ error: 'Invalid or expired refresh token' }, 401);
    }

    const now = Math.floor(Date.now() / 1000);
    if (now - authTime > env.MAX_SESSION_DAYS * 24 * 60 * 60) {
      return c.json({ error: 'Session expired, sign in again' }, 401);
    }

    // The service is stateless, so the old refresh token stays valid until
    // it expires. A server-side denylist would allow true revocation but
    // would mean storing per-user state; the MAX_SESSION_DAYS cap on
    // auth_time bounds how long any chain of refreshes can last instead.
    return c.json(await issueTokens(payload.sub, authTime));

  } catch (err) {
    console.error('Token refresh error:', err);
    return c.json({ error: 'Token refresh failed' }, 500);
  }
});

/**
 * Middleware to verify session token
 */
export async function verifySession(
  authHeader: string | undefined
): Promise<{ valid: boolean; userId?: string; error?: string }> {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return { valid: false, error: 'Missing or invalid Authorization header' };
  }

  const token = authHeader.slice(7);
  const secret = new TextEncoder().encode(env.JWT_SECRET);

  try {
    const { payload } = await jose.jwtVerify(token, secret);
    if (tokenTypeOf(payload) !== 'access' || !payload.sub) {
      return { valid: false, error: 'Invalid or expired token' };
    }
    return { valid: true, userId: payload.sub };
  } catch (err) {
    return { valid: false, error: 'Invalid or expired token' };
  }
}
