import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { authRoutes } from './routes/auth';
import { analyzeRoutes } from './routes/analyze';
import { analyzeVideoRoutes } from './routes/analyze-video';
import { uploadRoutes } from './routes/upload';
import { chatRoutes } from './routes/chat';

// Environment configuration
export interface Env {
  GOOGLE_CLIENT_ID: string;
  JWT_SECRET: string;
  ALLOWED_DOMAIN: string;
  RATE_LIMIT_PER_HOUR: number;
  GEMINI_API_KEY: string;
  GEMINI_TEXT_MODEL: string;
  GEMINI_VIDEO_MODEL: string;
  VIDEO_RATE_LIMIT_PER_HOUR: number;
  CHAT_RATE_LIMIT_PER_HOUR: number;
}

// Load environment variables
export const env: Env = {
  GOOGLE_CLIENT_ID: process.env.GOOGLE_CLIENT_ID || '',
  JWT_SECRET: process.env.JWT_SECRET || '',
  ALLOWED_DOMAIN: process.env.ALLOWED_DOMAIN || 'psd401.net',
  RATE_LIMIT_PER_HOUR: parseInt(process.env.RATE_LIMIT_PER_HOUR || '20', 10),
  GEMINI_API_KEY: process.env.GEMINI_API_KEY || '',
  GEMINI_TEXT_MODEL: process.env.GEMINI_TEXT_MODEL || 'gemini-3.1-pro-preview',
  GEMINI_VIDEO_MODEL: process.env.GEMINI_VIDEO_MODEL || 'gemini-3-flash-preview',
  VIDEO_RATE_LIMIT_PER_HOUR: parseInt(process.env.VIDEO_RATE_LIMIT_PER_HOUR || '5', 10),
  CHAT_RATE_LIMIT_PER_HOUR: parseInt(process.env.CHAT_RATE_LIMIT_PER_HOUR || '50', 10),
};

// Startup validation for critical security configuration
const MIN_JWT_SECRET_LENGTH = 32;
if (!env.JWT_SECRET || env.JWT_SECRET.length < MIN_JWT_SECRET_LENGTH) {
  throw new Error(`JWT_SECRET must be at least ${MIN_JWT_SECRET_LENGTH} characters for secure token signing`);
}

// SECURITY DESIGN DECISION: In-memory rate limiting
// - Resets on container restart and doesn't scale horizontally across instances
// - Acceptable for this low-traffic internal tool (@psd401.net domain-restricted)
// - Rate limiting here is courtesy throttling for authenticated users, not abuse protection
// - Primary protection comes from: auth middleware, Gemini API quotas, Cloud Run limits
// - If scaling becomes necessary, migrate to Cloud Memorystore (Redis)
export const rateLimitStore = new Map<string, { count: number; resetTime: number }>();

export function checkRateLimit(key: string, limit: number): { allowed: boolean; current: number; resetIn: number } {
  const now = Date.now();
  const hourMs = 3600000;
  const entry = rateLimitStore.get(key);

  if (!entry || now > entry.resetTime) {
    rateLimitStore.set(key, { count: 1, resetTime: now + hourMs });
    return { allowed: true, current: 1, resetIn: hourMs / 1000 };
  }

  if (entry.count >= limit) {
    return { allowed: false, current: entry.count, resetIn: (entry.resetTime - now) / 1000 };
  }

  entry.count++;
  return { allowed: true, current: entry.count, resetIn: (entry.resetTime - now) / 1000 };
}

export function getRateLimitStatus(key: string, limit: number): { used: number; limit: number; remaining: number; resets_in: number } {
  const now = Date.now();
  const entry = rateLimitStore.get(key);

  if (!entry || now > entry.resetTime) {
    return { used: 0, limit, remaining: limit, resets_in: 3600 };
  }

  return {
    used: entry.count,
    limit,
    remaining: Math.max(0, limit - entry.count),
    resets_in: (entry.resetTime - now) / 1000,
  };
}

const app = new Hono();

// SECURITY DESIGN DECISION: Permissive CORS (origin: '*')
// - iOS app uses native networking (CORS doesn't apply to native apps)
// - No web frontend exists for this application
// - All endpoints require @psd401.net Google OAuth authentication
// - CORS restrictions would only affect browser-based requests, which can't authenticate anyway
// - Keeping permissive avoids maintenance overhead with no security benefit for this architecture
app.use('*', cors({
  origin: '*',
  allowHeaders: ['Content-Type', 'Authorization'],
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
}));

// Security headers middleware
app.use('*', async (c, next) => {
  await next();
  c.header('X-Content-Type-Options', 'nosniff');
  c.header('X-Frame-Options', 'DENY');
});

// Health check
app.get('/', (c) => {
  return c.json({
    name: 'LessonLens API',
    version: '1.0.0',
    status: 'healthy',
    runtime: 'Cloud Run'
  });
});

// Mount routes
app.route('/auth', authRoutes);
app.route('/analyze', analyzeRoutes);
app.route('/analyze/video', analyzeVideoRoutes);
app.route('/upload', uploadRoutes);
app.route('/chat', chatRoutes);

// Error handler - logs details server-side, returns generic message to client
app.onError((err, c) => {
  console.error('Unhandled error:', err);
  return c.json({
    error: 'Internal server error'
  }, 500);
});

// 404 handler
app.notFound((c) => {
  return c.json({
    error: 'Not found',
    path: c.req.path
  }, 404);
});

// Start server
const port = parseInt(process.env.PORT || '8080', 10);
console.log(`Starting server on port ${port}...`);

export default {
  port,
  fetch: app.fetch,
};
