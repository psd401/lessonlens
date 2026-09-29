/**
 * Ownership checks for the older Gemini Files API video path (apps before
 * the Cloud Storage path; removed once those apps are retired).
 *
 * /upload/initiate names each file "<user hash>-<timestamp>-<name>", so a
 * file's displayName says who uploaded it without containing any user
 * details. Routes that take a Gemini file name look the file up and only
 * act on it when that prefix matches the caller.
 */

import { userHash } from './video-storage';

const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com';

export interface GeminiFile {
  name: string;
  displayName?: string;
  mimeType: string;
  uri: string;
  state: 'PROCESSING' | 'ACTIVE' | 'FAILED';
  [key: string]: unknown;
}

export function geminiDisplayNameFor(userId: string, timestamp: number, sanitizedFileName: string): string {
  return `${userHash(userId)}-${timestamp}-${sanitizedFileName}`;
}

/**
 * Returns the file when the caller uploaded it, or null when it doesn't
 * exist or belongs to someone else (callers answer 404 either way, so the
 * response doesn't reveal whether another user's file exists).
 */
export async function getOwnedGeminiFile(
  fileName: string,
  userId: string,
  apiKey: string
): Promise<GeminiFile | null> {
  const response = await globalThis.fetch(`${GEMINI_API_BASE}/v1beta/${fileName}?key=${apiKey}`);
  if (response.status === 404) {
    return null;
  }
  if (!response.ok) {
    throw new Error(`Gemini Files API returned ${response.status} reading file metadata`);
  }
  const file = await response.json() as GeminiFile;
  return file.displayName?.startsWith(`${userHash(userId)}-`) ? file : null;
}
