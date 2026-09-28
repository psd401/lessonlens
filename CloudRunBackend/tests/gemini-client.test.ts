/**
 * Tests for the Gemini client (bun test).
 *
 * fetch is replaced with a recorder, so no request leaves the machine. The
 * metadata server is simulated with the response shapes Cloud Run returns.
 */
import { describe, expect, test } from 'bun:test';
import { createGeminiClient, parseGeminiBackend, vertexHost } from '../src/gemini-client';

interface Call {
  url: string;
  init?: RequestInit;
}

function recordingFetch(tokenExpiresIn = 3600) {
  const calls: Call[] = [];
  let tokenCount = 0;
  const fetchFn = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init });
    if (url.endsWith('/project/project-id')) {
      return new Response('test-project\n');
    }
    if (url.endsWith('/instance/service-accounts/default/token')) {
      tokenCount++;
      return Response.json({ access_token: `token-${tokenCount}`, expires_in: tokenExpiresIn });
    }
    return Response.json({ candidates: [] });
  }) as typeof fetch;
  return { fetchFn, calls };
}

const body = { contents: [{ role: 'user', parts: [{ text: 'hello' }] }] };

describe('apikey backend', () => {
  test('posts to the Gemini Developer API with the key and never calls the metadata server', async () => {
    const { fetchFn, calls } = recordingFetch();
    const client = createGeminiClient({ backend: 'apikey', apiKey: 'k123', vertexLocation: 'global', fetch: fetchFn });

    await client.generateContent('gemini-3.8-flash', body);

    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=k123'
    );
    expect(calls[0].init?.method).toBe('POST');
    expect(JSON.parse(String(calls[0].init?.body))).toEqual(body);
  });
});

describe('vertex backend', () => {
  test('posts to the Vertex global endpoint with a bearer token and the metadata project', async () => {
    const { fetchFn, calls } = recordingFetch();
    const client = createGeminiClient({ backend: 'vertex', apiKey: '', vertexLocation: 'global', fetch: fetchFn });

    await client.generateContent('gemini-3.8-flash', body);

    const metadataCalls = calls.filter((c) => c.url.startsWith('http://metadata.google.internal/'));
    expect(metadataCalls).toHaveLength(2);
    for (const c of metadataCalls) {
      expect(new Headers(c.init?.headers).get('Metadata-Flavor')).toBe('Google');
    }

    const gemini = calls[calls.length - 1];
    expect(gemini.url).toBe(
      'https://aiplatform.googleapis.com/v1/projects/test-project/locations/global/publishers/google/models/gemini-3.8-flash:generateContent'
    );
    expect(gemini.url).not.toContain('key=');
    expect(new Headers(gemini.init?.headers).get('Authorization')).toBe('Bearer token-1');
    expect(JSON.parse(String(gemini.init?.body))).toEqual(body);
  });

  test('reuses the token and project across requests', async () => {
    const { fetchFn, calls } = recordingFetch();
    const client = createGeminiClient({ backend: 'vertex', apiKey: '', vertexLocation: 'global', fetch: fetchFn });

    await client.generateContent('m', body);
    await client.generateContent('m', body);

    expect(calls.filter((c) => c.url.includes('metadata.google.internal'))).toHaveLength(2);
    expect(new Headers(calls[calls.length - 1].init?.headers).get('Authorization')).toBe('Bearer token-1');
  });

  test('refreshes a token that is about to expire', async () => {
    // A 30-second token is inside the 60-second refresh margin
    const { fetchFn, calls } = recordingFetch(30);
    const client = createGeminiClient({ backend: 'vertex', apiKey: '', vertexLocation: 'global', fetch: fetchFn });

    await client.generateContent('m', body);
    await client.generateContent('m', body);

    expect(calls.filter((c) => c.url.endsWith('/token'))).toHaveLength(2);
    expect(new Headers(calls[calls.length - 1].init?.headers).get('Authorization')).toBe('Bearer token-2');
  });

  test('throws when the metadata server fails, without calling Gemini', async () => {
    const calls: string[] = [];
    const failing = (async (input: RequestInfo | URL) => {
      calls.push(String(input));
      return new Response('nope', { status: 500 });
    }) as typeof fetch;
    const client = createGeminiClient({ backend: 'vertex', apiKey: '', vertexLocation: 'global', fetch: failing });

    await expect(client.generateContent('m', body)).rejects.toThrow('Metadata server returned 500');
    expect(calls.some((u) => u.includes('aiplatform'))).toBe(false);
  });
});

describe('config helpers', () => {
  test('GEMINI_BACKEND defaults to apikey and rejects unknown values', () => {
    expect(parseGeminiBackend(undefined)).toBe('apikey');
    expect(parseGeminiBackend('')).toBe('apikey');
    expect(parseGeminiBackend('vertex')).toBe('vertex');
    expect(() => parseGeminiBackend('Vertex')).toThrow();
  });

  test('regional locations use the regional Vertex host', () => {
    expect(vertexHost('global')).toBe('aiplatform.googleapis.com');
    expect(vertexHost('us-west1')).toBe('us-west1-aiplatform.googleapis.com');
  });
});
