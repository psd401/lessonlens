/**
 * Review finding SEC-07: Gemini replies can quote the transcript, so failed
 * or unusable replies must be logged by counts and enum fields only.
 *
 * Runs the real Hono app with a signed session token and a fake fetch that
 * plays Gemini. Each reply carries a marker string; the marker must never
 * reach console.error, while the enum fields still do.
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import './test-env';
import * as jose from 'jose';

const { default: server } = await import('../src/index');

// One identifier, so a JSON.parse error that quotes it would quote all of it
const MARKER = 'StudentQuoteMarker7f3a';
const realFetch = globalThis.fetch;
const realConsoleError = console.error;

let geminiReply: unknown;
let logged: string[];

beforeEach(() => {
  logged = [];
  console.error = (...args: unknown[]) => {
    logged.push(args.map((a) => (a instanceof Error ? `${a.name}: ${a.message}` : String(a))).join(' '));
  };
  globalThis.fetch = (async () => Response.json(geminiReply)) as unknown as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = realFetch;
  console.error = realConsoleError;
});

async function post(path: string, body: unknown): Promise<Response> {
  const token = await new jose.SignJWT({ token_type: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(`logging-test-${path}`)
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(new TextEncoder().encode(process.env.JWT_SECRET));
  return server.fetch(
    new Request(`http://localhost${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(body),
    })
  );
}

const technique = { id: 't1', name: 'Wait Time', description: 'd', lookFors: [], exemplarPhrases: [] };
const analyze = () => post('/analyze', { transcript: 'Fictional lesson.', techniques: [technique] });
const chat = () =>
  post('/chat', {
    transcript: 'Fictional lesson.',
    analysis_summary: 'Summary',
    technique_evaluations_summary: '',
    messages: [{ role: 'user', content: 'How did wait time go?' }],
    technique_names: ['Wait Time'],
  });

const allLogs = () => logged.join('\n');

describe('unusable Gemini replies are logged without their content', () => {
  test('blocked analysis: logs the block reason, not the reply', async () => {
    geminiReply = { promptFeedback: { blockReason: 'SAFETY', safetyRatings: [{ note: MARKER }] }, modelVersion: MARKER };

    expect((await analyze()).status).toBe(502);
    expect(allLogs()).toContain('blockReason=SAFETY');
    expect(allLogs()).toContain('candidates=0');
    expect(allLogs()).not.toContain(MARKER);
  });

  test('analysis reply that is not JSON: logs the error name and length only', async () => {
    // JSON.parse errors quote the first token of the bad input
    const text = `${MARKER} said the answer was {not json`;
    geminiReply = { candidates: [{ content: { parts: [{ text }] }, finishReason: 'STOP' }] };

    expect((await analyze()).status).toBe(502);
    expect(allLogs()).toContain(`length=${text.length}`);
    expect(allLogs()).not.toContain(MARKER);
  });

  test('chat candidate with no text: logs the finish reason, not the candidate', async () => {
    geminiReply = { candidates: [{ content: { parts: [{ note: MARKER }] }, finishReason: 'MAX_TOKENS' }] };

    expect((await chat()).status).toBe(502);
    expect(allLogs()).toContain('finishReason=MAX_TOKENS');
    expect(allLogs()).not.toContain(MARKER);
  });

  test('a non-enum finish reason is dropped rather than logged', async () => {
    geminiReply = { candidates: [{ content: { parts: [] }, finishReason: `quoted: ${MARKER}` }] };

    expect((await chat()).status).toBe(502);
    expect(allLogs()).toContain('finishReason=');
    expect(allLogs()).not.toContain(MARKER);
  });

  test('a Gemini error body is logged by status fields only', async () => {
    globalThis.fetch = (async () =>
      Response.json({ error: { status: 'INVALID_ARGUMENT', message: `Bad input near ${MARKER}` } }, { status: 400 })) as unknown as typeof fetch;

    expect((await analyze()).status).toBeGreaterThanOrEqual(400);
    expect(allLogs()).toContain('INVALID_ARGUMENT');
    expect(allLogs()).not.toContain(MARKER);
  });
});
