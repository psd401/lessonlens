/**
 * Temporary Cloud Storage for lesson videos sent to Vertex AI.
 *
 * Each upload goes to uploads/<hash of user ID>/<random UUID>.<ext>, so an
 * object name never contains who uploaded it, and /analyze/video can check
 * that the caller owns the object before sending it to Vertex. Objects are
 * deleted as soon as analysis finishes; the bucket's 1-day lifecycle rule is
 * the backstop.
 */

import { createHash } from 'node:crypto';
import type { GcpAuth } from './gcp-auth';

const STORAGE_API = 'https://storage.googleapis.com';

export const VIDEO_EXTENSIONS: Record<string, string> = {
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'video/x-m4v': 'm4v',
  'video/webm': 'webm',
};

export interface VideoObject {
  name: string;
  size: number;
  contentType: string;
}

export interface VideoStorageConfig {
  bucket: string;
  auth: GcpAuth;
  fetch?: typeof fetch;
}

export interface VideoStorage {
  newObjectName(userId: string, contentType: string): string;
  isOwnedBy(userId: string, objectName: string): boolean;
  startResumableUpload(objectName: string, contentType: string, size: number): Promise<string>;
  getObject(objectName: string): Promise<VideoObject | null>;
  deleteObject(objectName: string): Promise<void>;
  gsUri(objectName: string): string;
}

function userFolder(userId: string): string {
  const hash = createHash('sha256').update(userId).digest('hex').slice(0, 32);
  return `uploads/${hash}/`;
}

const OBJECT_FILE_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(mp4|mov|m4v|webm)$/;

export function createVideoStorage(config: VideoStorageConfig): VideoStorage {
  const fetchFn = (input: string, init: RequestInit) => (config.fetch ?? globalThis.fetch)(input, init);
  const bucket = encodeURIComponent(config.bucket);

  async function authHeaders(): Promise<Record<string, string>> {
    return { Authorization: `Bearer ${await config.auth.getAccessToken()}` };
  }

  return {
    newObjectName(userId: string, contentType: string): string {
      const ext = VIDEO_EXTENSIONS[contentType];
      if (!ext) {
        throw new Error(`Unsupported video content type: ${contentType}`);
      }
      return `${userFolder(userId)}${crypto.randomUUID()}.${ext}`;
    },

    isOwnedBy(userId: string, objectName: string): boolean {
      const folder = userFolder(userId);
      return objectName.startsWith(folder) && OBJECT_FILE_PATTERN.test(objectName.slice(folder.length));
    },

    async startResumableUpload(objectName: string, contentType: string, size: number): Promise<string> {
      const response = await fetchFn(
        `${STORAGE_API}/upload/storage/v1/b/${bucket}/o?uploadType=resumable&name=${encodeURIComponent(objectName)}`,
        {
          method: 'POST',
          headers: {
            ...(await authHeaders()),
            'Content-Type': 'application/json; charset=UTF-8',
            'X-Upload-Content-Type': contentType,
            'X-Upload-Content-Length': String(size),
          },
          body: JSON.stringify({ contentType }),
        }
      );
      if (!response.ok) {
        throw new Error(`Cloud Storage returned ${response.status} starting an upload`);
      }
      const sessionUrl = response.headers.get('Location');
      if (!sessionUrl) {
        throw new Error('Cloud Storage returned no upload session URL');
      }
      return sessionUrl;
    },

    async getObject(objectName: string): Promise<VideoObject | null> {
      const response = await fetchFn(
        `${STORAGE_API}/storage/v1/b/${bucket}/o/${encodeURIComponent(objectName)}?fields=name,size,contentType`,
        { method: 'GET', headers: await authHeaders() }
      );
      if (response.status === 404) {
        return null;
      }
      if (!response.ok) {
        throw new Error(`Cloud Storage returned ${response.status} reading object metadata`);
      }
      const body = await response.json() as { name: string; size: string; contentType: string };
      return { name: body.name, size: Number(body.size), contentType: body.contentType };
    },

    async deleteObject(objectName: string): Promise<void> {
      const response = await fetchFn(
        `${STORAGE_API}/storage/v1/b/${bucket}/o/${encodeURIComponent(objectName)}`,
        { method: 'DELETE', headers: await authHeaders() }
      );
      if (!response.ok && response.status !== 404) {
        throw new Error(`Cloud Storage returned ${response.status} deleting an object`);
      }
    },

    gsUri(objectName: string): string {
      return `gs://${config.bucket}/${objectName}`;
    },
  };
}
