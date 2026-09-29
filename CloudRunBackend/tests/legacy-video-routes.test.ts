/**
 * Ownership checks on the older Gemini Files API video path (bun test).
 *
 * Runs the real Hono app with signed session tokens. globalThis.fetch is a
 * fake Gemini API that remembers each file's displayName, so no request
 * leaves the machine.
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import './test-env';
import * as jose from 'jose';
import { userHash } from '../src/video-storage';

const { default: server } = await import('../src/index');

const realFetch = globalThis.fetch;

interface Call {
  method: string;
  pathname: string;
  body?: string;
}

let calls: Call[];
let files: Map<string, string>; // file name -> displayName

beforeEach(() => {
  calls = [];
  files = new Map([
    ['files/own123', `${userHash('user-123')}-1-lesson.mp4`],
    ['files/other456', `${userHash('user-456')}-1-lesson.mp4`],
    ['files/unprefixed', '1727000000000-lesson.mp4'],
  ]);
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input));
    const method = init?.method ?? 'GET';
    calls.push({ method, pathname: url.pathname, body: typeof init?.body === 'string' ? init.body : undefined });
    if (url.hostname !== 'generativelanguage.googleapis.com') {
      throw new Error(`Unexpected fetch in test: ${method} ${url}`);
    }
    if (url.pathname === '/upload/v1beta/files') {
      return new Response(null, { headers: { 'X-Goog-Upload-URL': 'https://upload.example/session/1' } });
    }
    if (url.pathname.endsWith(':generateContent')) {
      return Response.json({
        candidates: [{ content: { parts: [{ text: JSON.stringify({ overallSummary: 'Summary' }) }] } }],
      });
    }
    const name = url.pathname.replace('/v1beta/', '');
    if (method === 'DELETE') {
      return Response.json({});
    }
    const displayName = files.get(name);
    if (!displayName) {
      return new Response(null, { status: 404 });
    }
    return Response.json({
      name,
      displayName,
      mimeType: 'video/mp4',
      uri: `https://generativelanguage.googleapis.com/v1beta/${name}`,
      state: 'ACTIVE',
    });
  }) as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

async function request(method: string, path: string, userId: string, body?: unknown): Promise<Response> {
  const token = await new jose.SignJWT({})
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setExpirationTime('1h')
    .sign(new TextEncoder().encode(process.env.JWT_SECRET));
  return server.fetch(
    new Request(`http://localhost${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  );
}

const techniques = [{ id: 't1', name: 'Wait time', description: 'd', lookFors: [], exemplarPhrases: [] }];
const generated = () => calls.some((c) => c.pathname.endsWith(':generateContent'));
const deleted = () => calls.some((c) => c.method === 'DELETE');

describe('POST /upload/initiate', () => {
  test('names the Gemini file with the uploader\'s hash', async () => {
    const res = await request('POST', '/upload/initiate', 'user-123', {
      fileName: 'lesson.mp4',
      contentType: 'video/mp4',
      fileSize: 1000,
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { fileDisplayName: string };
    expect(body.fileDisplayName.startsWith(`${userHash('user-123')}-`)).toBe(true);
    expect(JSON.parse(calls[0].body!).file.displayName).toBe(body.fileDisplayName);
  });
});

describe('POST /upload/status', () => {
  test('returns the caller\'s own file', async () => {
    const res = await request('POST', '/upload/status', 'user-123', { fileName: 'files/own123' });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { state: string }).state).toBe('ACTIVE');
  });

  test('another user\'s file, an unprefixed file, and a missing file are all 404', async () => {
    for (const fileName of ['files/other456', 'files/unprefixed', 'files/missing']) {
      const res = await request('POST', '/upload/status', 'user-123', { fileName });
      expect(res.status).toBe(404);
    }
  });
});

describe('DELETE /upload/:fileName', () => {
  test('deletes the caller\'s own file', async () => {
    const res = await request('DELETE', '/upload/files/own123', 'user-123');
    expect(res.status).toBe(200);
    expect(deleted()).toBe(true);
  });

  test('refuses another user\'s file without deleting it', async () => {
    const res = await request('DELETE', '/upload/files/other456', 'user-123');
    expect(res.status).toBe(404);
    expect(deleted()).toBe(false);
  });
});

describe('POST /analyze/video with geminiFileName', () => {
  test('analyzes the caller\'s own file and then deletes it', async () => {
    const res = await request('POST', '/analyze/video', 'user-123', { geminiFileName: 'files/own123', techniques });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { overall_summary: string }).overall_summary).toBe('Summary');
    expect(generated()).toBe(true);
    expect(deleted()).toBe(true);
  });

  test('another user\'s file is 404, never analyzed, and never deleted', async () => {
    const res = await request('POST', '/analyze/video', 'user-123', { geminiFileName: 'files/other456', techniques });
    expect(res.status).toBe(404);
    expect(generated()).toBe(false);
    expect(deleted()).toBe(false);
  });
});
