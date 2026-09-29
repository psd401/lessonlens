/**
 * Route tests for the Cloud Storage video path (bun test).
 *
 * Runs the real Hono app with a signed session token. globalThis.fetch is
 * replaced with a fake that plays the metadata server, Cloud Storage and
 * Vertex AI, so no request leaves the machine.
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import './test-env';
import * as jose from 'jose';

const { default: server } = await import('../src/index');

const realFetch = globalThis.fetch;

interface Call {
  url: string;
  method: string;
  body?: string;
}

let calls: Call[];

const hostOf = (call: Call) => new URL(call.url).hostname;
const isStorage = (call: Call) => hostOf(call) === 'storage.googleapis.com';
const isVertex = (call: Call) => hostOf(call) === 'aiplatform.googleapis.com' || hostOf(call).endsWith('.rep.googleapis.com');
let vertexStatus: number;
let objectExists: boolean;

const analysisJson = {
  overallSummary: 'Summary',
  strengths: ['Clear objective'],
  growthAreas: [],
  actionableNextSteps: [],
  techniqueEvaluations: [{ techniqueId: 't1', wasObserved: true, rating: 3, evidence: [], feedback: 'f', suggestions: [] }],
};

beforeEach(() => {
  calls = [];
  vertexStatus = 200;
  objectExists = true;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? 'GET';
    const call = { url, method, body: typeof init?.body === 'string' ? init.body : undefined };
    calls.push(call);
    const { pathname, searchParams } = new URL(url);

    if (url.endsWith('/project/project-id')) return new Response('test-project');
    if (url.endsWith('/service-accounts/default/token')) {
      return Response.json({ access_token: 'test-token', expires_in: 3600 });
    }
    if (isStorage(call) && searchParams.get('uploadType') === 'resumable') {
      return new Response(null, { headers: { Location: 'https://storage.example/session/1' } });
    }
    if (isStorage(call) && pathname.startsWith('/storage/v1/') && method === 'GET') {
      return objectExists
        ? Response.json({ name: 'x', size: '1000', contentType: 'video/mp4' })
        : new Response(null, { status: 404 });
    }
    if (isStorage(call) && pathname.startsWith('/storage/v1/') && method === 'DELETE') {
      return new Response(null, { status: 204 });
    }
    if (isVertex(call)) {
      if (vertexStatus !== 200) {
        return Response.json({ error: { status: 'INVALID_ARGUMENT' } }, { status: vertexStatus });
      }
      return Response.json({
        candidates: [{ content: { parts: [{ text: JSON.stringify(analysisJson) }] } }],
        usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 20 },
      });
    }
    throw new Error(`Unexpected fetch in test: ${method} ${url}`);
  }) as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

async function sessionFor(userId: string): Promise<string> {
  return new jose.SignJWT({})
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setExpirationTime('1h')
    .sign(new TextEncoder().encode(process.env.JWT_SECRET));
}

async function post(path: string, userId: string, body: unknown): Promise<Response> {
  return server.fetch(
    new Request(`http://localhost${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await sessionFor(userId)}` },
      body: JSON.stringify(body),
    })
  );
}

async function initiate(userId: string): Promise<string> {
  const res = await post('/upload/initiate/gcs', userId, { contentType: 'video/mp4', fileSize: 1000 });
  const body = (await res.json()) as { objectName: string };
  calls = [];
  return body.objectName;
}

const techniques = [{ id: 't1', name: 'Wait time', description: 'd', lookFors: [], exemplarPhrases: [] }];

describe('POST /upload/initiate/gcs', () => {
  test('returns the session URL and an object name in the caller\'s folder', async () => {
    const res = await post('/upload/initiate/gcs', 'user-123', { contentType: 'video/mp4', fileSize: 1000 });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { uploadUrl: string; objectName: string };
    expect(body.uploadUrl).toBe('https://storage.example/session/1');
    expect(body.objectName).toMatch(/^uploads\/[0-9a-f]{32}\/[0-9a-f-]{36}\.mp4$/);
    expect(calls.some((c) => c.url.includes('/b/test-video-bucket/') && c.url.includes('uploadType=resumable'))).toBe(true);
  });

  test('rejects unsupported types and oversize files before calling Cloud Storage', async () => {
    expect((await post('/upload/initiate/gcs', 'user-123', { contentType: 'text/plain', fileSize: 1 })).status).toBe(400);
    expect(
      (await post('/upload/initiate/gcs', 'user-123', { contentType: 'video/mp4', fileSize: 3 * 1024 ** 3 })).status
    ).toBe(400);
    expect(calls.some(isStorage)).toBe(false);
  });
});

describe('POST /analyze/video with gcsObject', () => {
  test('sends the gs:// video to Vertex, returns the analysis, and deletes the object', async () => {
    const objectName = await initiate('user-123');

    const res = await post('/analyze/video', 'user-123', { gcsObject: objectName, techniques });

    expect(res.status).toBe(200);
    const body = (await res.json()) as { overall_summary: string; technique_evaluations: unknown[] };
    expect(body.overall_summary).toBe('Summary');
    expect(body.technique_evaluations).toHaveLength(1);

    const vertex = calls.find(isVertex)!;
    const request = JSON.parse(vertex.body!);
    expect(request.contents[0].role).toBe('user');
    expect(request.contents[0].parts[0].fileData).toEqual({
      mimeType: 'video/mp4',
      fileUri: `gs://test-video-bucket/${objectName}`,
    });
    expect(calls.some((c) => c.method === 'DELETE' && c.url.includes(encodeURIComponent(objectName)))).toBe(true);
  });

  test('another user\'s object is not found and never reaches Cloud Storage or Vertex', async () => {
    const objectName = await initiate('user-456');

    const res = await post('/analyze/video', 'user-123', { gcsObject: objectName, techniques });

    expect(res.status).toBe(404);
    expect(calls.some((c) => isStorage(c) || isVertex(c))).toBe(false);
  });

  test('a Vertex rejection is reported with its status and the object is still deleted', async () => {
    const objectName = await initiate('user-123');
    vertexStatus = 400;

    const res = await post('/analyze/video', 'user-123', { gcsObject: objectName, techniques });

    expect(res.status).toBe(502);
    expect(((await res.json()) as { status: number }).status).toBe(400);
    expect(calls.some((c) => c.method === 'DELETE')).toBe(true);
  });

  test('a missing upload returns 404 without calling Vertex', async () => {
    const objectName = await initiate('user-123');
    objectExists = false;

    const res = await post('/analyze/video', 'user-123', { gcsObject: objectName, techniques });

    expect(res.status).toBe(404);
    expect(calls.some(isVertex)).toBe(false);
  });

  test('sending both gcsObject and geminiFileName is rejected', async () => {
    const objectName = await initiate('user-123');
    const res = await post('/analyze/video', 'user-123', {
      gcsObject: objectName,
      geminiFileName: 'files/abc',
      techniques,
    });
    expect(res.status).toBe(400);
  });
});
