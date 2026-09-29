/**
 * Tests for the temporary video storage helper (bun test). fetch is a
 * recorder, so nothing leaves the machine.
 */
import { describe, expect, test } from 'bun:test';
import { createVideoStorage } from '../src/video-storage';
import type { GcpAuth } from '../src/gcp-auth';

const auth: GcpAuth = {
  getProjectId: async () => 'test-project',
  getAccessToken: async () => 'test-token',
};

function recorder(respond: (url: string, init?: RequestInit) => Response) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const fetchFn = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init });
    return respond(url, init);
  }) as typeof fetch;
  return { fetchFn, calls };
}

function storageWith(respond: (url: string, init?: RequestInit) => Response) {
  const { fetchFn, calls } = recorder(respond);
  return { storage: createVideoStorage({ bucket: 'video-tmp', auth, fetch: fetchFn }), calls };
}

describe('object names', () => {
  const { storage } = storageWith(() => new Response());

  test('are under a hashed per-user folder with a UUID and the right extension', () => {
    const name = storage.newObjectName('user-123', 'video/quicktime');
    expect(name).toMatch(/^uploads\/[0-9a-f]{32}\/[0-9a-f-]{36}\.mov$/);
    expect(name).not.toContain('user-123');
    expect(storage.newObjectName('user-123', 'video/mp4').split('/')[1]).toBe(name.split('/')[1]);
  });

  test('reject unsupported content types', () => {
    expect(() => storage.newObjectName('user-123', 'text/plain')).toThrow();
  });

  test('ownership accepts only the caller\'s own well-formed names', () => {
    const own = storage.newObjectName('user-123', 'video/mp4');
    const other = storage.newObjectName('user-456', 'video/mp4');
    const folder = own.slice(0, own.lastIndexOf('/') + 1);

    expect(storage.isOwnedBy('user-123', own)).toBe(true);
    expect(storage.isOwnedBy('user-123', other)).toBe(false);
    expect(storage.isOwnedBy('user-123', `${folder}../${other.split('/')[1]}/x.mp4`)).toBe(false);
    expect(storage.isOwnedBy('user-123', `${folder}not-a-uuid.mp4`)).toBe(false);
    expect(storage.isOwnedBy('user-123', own.replace(/\.mp4$/, '.exe'))).toBe(false);
    expect(storage.isOwnedBy('user-123', `${own}/extra`)).toBe(false);
  });

  test('gs URIs point at the bucket', () => {
    expect(storage.gsUri('uploads/a/b.mp4')).toBe('gs://video-tmp/uploads/a/b.mp4');
  });
});

describe('Cloud Storage requests', () => {
  test('starting an upload posts a resumable session and returns its URL', async () => {
    const { storage, calls } = storageWith(
      () => new Response(null, { status: 200, headers: { Location: 'https://storage.example/session/1' } })
    );

    const url = await storage.startResumableUpload('uploads/f/x.mp4', 'video/mp4', 1234);

    expect(url).toBe('https://storage.example/session/1');
    expect(calls[0].url).toBe(
      'https://storage.googleapis.com/upload/storage/v1/b/video-tmp/o?uploadType=resumable&name=uploads%2Ff%2Fx.mp4'
    );
    const headers = new Headers(calls[0].init?.headers);
    expect(calls[0].init?.method).toBe('POST');
    expect(headers.get('Authorization')).toBe('Bearer test-token');
    expect(headers.get('X-Upload-Content-Type')).toBe('video/mp4');
    expect(headers.get('X-Upload-Content-Length')).toBe('1234');
  });

  test('starting an upload fails on an error status or a missing session URL', async () => {
    const failing = storageWith(() => new Response(null, { status: 403 })).storage;
    await expect(failing.startResumableUpload('uploads/f/x.mp4', 'video/mp4', 1)).rejects.toThrow('403');

    const noLocation = storageWith(() => new Response(null, { status: 200 })).storage;
    await expect(noLocation.startResumableUpload('uploads/f/x.mp4', 'video/mp4', 1)).rejects.toThrow('no upload session');
  });

  test('object metadata is parsed, and a missing object is null', async () => {
    const found = storageWith(() =>
      Response.json({ name: 'uploads/f/x.mp4', size: '2048', contentType: 'video/mp4' })
    );
    expect(await found.storage.getObject('uploads/f/x.mp4')).toEqual({
      name: 'uploads/f/x.mp4',
      size: 2048,
      contentType: 'video/mp4',
    });
    expect(found.calls[0].url).toBe(
      'https://storage.googleapis.com/storage/v1/b/video-tmp/o/uploads%2Ff%2Fx.mp4?fields=name,size,contentType'
    );

    const missing = storageWith(() => new Response(null, { status: 404 })).storage;
    expect(await missing.getObject('uploads/f/x.mp4')).toBeNull();
  });

  test('deleting treats 404 as done and throws on other errors', async () => {
    const gone = storageWith(() => new Response(null, { status: 404 }));
    await gone.storage.deleteObject('uploads/f/x.mp4');
    expect(gone.calls[0].init?.method).toBe('DELETE');

    const failing = storageWith(() => new Response(null, { status: 500 })).storage;
    await expect(failing.deleteObject('uploads/f/x.mp4')).rejects.toThrow('500');
  });
});
