/**
 * Review finding SEC-05: oversized prompt fields are rejected with 400
 * before any Gemini call, and oversized bodies with 413.
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import './test-env';
import * as jose from 'jose';
import { LIMITS, MAX_BODY_BYTES } from '../src/input-limits';

const { default: server, videoStorage } = await import('../src/index');

const realFetch = globalThis.fetch;
const METADATA = 'http://metadata.google.internal/';
// Vertex calls first ask the metadata server for the project and a token
function metadataReply(url: string): Response | null {
  if (!url.startsWith(METADATA)) return null;
  return url.endsWith('/project/project-id')
    ? new Response('test-project')
    : Response.json({ access_token: 'test-token', expires_in: 3600 });
}

let geminiCalls = 0;
let userCount = 0;

beforeEach(() => {
  geminiCalls = 0;
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const metadata = metadataReply(String(input));
    if (metadata) return metadata;
    geminiCalls++;
    const text = JSON.stringify({ overallSummary: 'ok', strengths: [], growthAreas: [], actionableNextSteps: [], techniqueEvaluations: [] });
    return Response.json({ candidates: [{ content: { parts: [{ text }] }, finishReason: 'STOP' }] });
  }) as unknown as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

// A fresh user per request by default, so the shared rate limiter never interferes
async function post(path: string, body: unknown, subject = `limits-test-${++userCount}`): Promise<Response> {
  const token = await new jose.SignJWT({ token_type: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(subject)
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(new TextEncoder().encode(process.env.JWT_SECRET));
  return server.fetch(
    new Request(`http://localhost${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: typeof body === 'string' ? body : JSON.stringify(body),
    })
  );
}

const s = (n: number) => 'x'.repeat(n);
const technique = (overrides = {}) => ({
  id: 'wait-time',
  name: 'Wait Time',
  description: 'Pause after asking a question.',
  lookFors: ['Teacher pauses 3+ seconds'],
  exemplarPhrases: ['Take a moment to think.'],
  ...overrides,
});
const chatBody = (overrides = {}) => ({
  transcript: 'Fictional lesson.',
  analysis_summary: 'Summary',
  technique_evaluations_summary: 'Wait Time: observed',
  messages: [{ role: 'user', content: 'How did wait time go?' }],
  technique_names: ['Wait Time'],
  ...overrides,
});

describe('/analyze field caps', () => {
  test('an oversized technique description is rejected before Gemini', async () => {
    const res = await post('/analyze', { transcript: 'Hi.', techniques: [technique({ description: s(LIMITS.techniqueDescription + 1) })] });
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ field: 'techniques[0].description', maxLength: LIMITS.techniqueDescription });
    expect(geminiCalls).toBe(0);
  });

  test('too many look-fors is rejected', async () => {
    const res = await post('/analyze', { transcript: 'Hi.', techniques: [technique({ lookFors: Array(LIMITS.techniqueListItems + 1).fill('a') })] });
    expect(res.status).toBe(400);
    expect(geminiCalls).toBe(0);
  });

  test('a non-string field is rejected', async () => {
    const res = await post('/analyze', { transcript: 'Hi.', techniques: [technique({ name: { nested: true } })] });
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ field: 'techniques[0].name' });
  });

  test('oversized pause text is rejected', async () => {
    const pauseData = {
      pauses: [{ startTime: 0, endTime: 4, duration: 4, precedingText: s(LIMITS.pauseText + 1), followingText: 'ok' }],
      summary: { count: 1, averageDuration: 4, maxDuration: 4, totalPauseTime: 4 },
    };
    const res = await post('/analyze', { transcript: 'Hi.', techniques: [technique()], pauseData });
    expect(res.status).toBe(400);
    expect(geminiCalls).toBe(0);
  });

  test('20 techniques at every cap are accepted', async () => {
    const maxed = technique({
      id: s(LIMITS.techniqueId),
      name: s(LIMITS.techniqueName),
      description: s(LIMITS.techniqueDescription),
      lookFors: Array(LIMITS.techniqueListItems).fill(s(LIMITS.techniqueListItem)),
      exemplarPhrases: Array(LIMITS.techniqueListItems).fill(s(LIMITS.techniqueListItem)),
    });
    const res = await post('/analyze', { transcript: s(100_000), techniques: Array(20).fill(maxed) });
    expect(res.status).toBe(200);
    expect(geminiCalls).toBe(1);
  });
});

describe('/analyze/video field caps', () => {
  test('an oversized technique is rejected', async () => {
    const subject = 'limits-video-user';
    const gcsObject = videoStorage!.newObjectName(subject, 'video/mp4');
    const res = await post('/analyze/video', { gcsObject, techniques: [technique({ name: s(LIMITS.techniqueName + 1) })] }, subject);
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ field: 'techniques[0].name' });
    expect(geminiCalls).toBe(0);
  });
});

describe('/chat field caps', () => {
  test('an oversized message is rejected before Gemini', async () => {
    const res = await post('/chat', chatBody({ messages: [{ role: 'user', content: s(LIMITS.chatMessage + 1) }] }));
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ field: 'messages[0].content' });
    expect(geminiCalls).toBe(0);
  });

  test('messages that are not a list are rejected', async () => {
    const res = await post('/chat', chatBody({ messages: { role: 'user', content: 'hi' } }));
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ field: 'messages' });
  });

  test('an oversized summary is rejected', async () => {
    const res = await post('/chat', chatBody({ analysis_summary: s(LIMITS.analysisSummary + 1) }));
    expect(res.status).toBe(400);
    expect(geminiCalls).toBe(0);
  });

  test('an oversized reflection is rejected', async () => {
    const res = await post('/chat', chatBody({ reflection_summary: s(LIMITS.reflectionSummary + 1) }));
    expect(res.status).toBe(400);
    expect(geminiCalls).toBe(0);
  });

  test('a request at every cap is accepted', async () => {
    const messages = Array.from({ length: 50 }, (_, i) => ({ role: i % 2 ? 'assistant' : 'user', content: s(LIMITS.chatMessage) }));
    const res = await post('/chat', chatBody({
      transcript: s(100_000),
      analysis_summary: s(LIMITS.analysisSummary),
      technique_evaluations_summary: s(LIMITS.techniqueEvaluationsSummary),
      reflection_summary: s(LIMITS.reflectionSummary),
      messages,
      technique_names: Array(LIMITS.techniqueNames).fill(s(LIMITS.techniqueNameEntry)),
    }));
    expect(res.status).toBe(200);
    expect(geminiCalls).toBe(1);
  });
});

describe('total body cap', () => {
  test('a body over the cap gets 413 on /analyze and /chat', async () => {
    const big = JSON.stringify({ transcript: s(MAX_BODY_BYTES), techniques: [technique()] });
    expect((await post('/analyze', big)).status).toBe(413);
    expect((await post('/chat', big)).status).toBe(413);
    expect(geminiCalls).toBe(0);
  });
});
