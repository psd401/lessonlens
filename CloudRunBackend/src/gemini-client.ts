/**
 * Sends generateContent requests to Gemini through one of two backends:
 *
 * - "apikey": the Gemini Developer API (generativelanguage.googleapis.com)
 *   with GEMINI_API_KEY. Kept as a manual fallback during the Vertex move.
 * - "vertex": Vertex AI in the Cloud Run project, authenticated as the
 *   service's runtime service account (see gcp-auth.ts).
 *
 * Both backends take the same request body and return the same response and
 * error shapes, so callers handle either one identically.
 */

import { createMetadataAuth, type GcpAuth } from './gcp-auth';

export type GeminiBackend = 'apikey' | 'vertex';

export interface GeminiClientConfig {
  backend: GeminiBackend;
  apiKey: string;
  vertexLocation: string;
  auth?: GcpAuth;
  fetch?: typeof fetch;
}

export interface GeminiClient {
  generateContent(model: string, body: unknown): Promise<Response>;
}

const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com';

// Multi-region locations use their own hostnames; they keep ML processing
// inside that jurisdiction (the global endpoint does not)
const MULTI_REGION_LOCATIONS = new Set(['us', 'eu']);

export function parseGeminiBackend(value: string | undefined): GeminiBackend {
  const backend = value || 'apikey';
  if (backend !== 'apikey' && backend !== 'vertex') {
    throw new Error(`GEMINI_BACKEND must be "apikey" or "vertex", got "${backend}"`);
  }
  return backend;
}

export function vertexHost(location: string): string {
  if (location === 'global') {
    return 'aiplatform.googleapis.com';
  }
  if (MULTI_REGION_LOCATIONS.has(location)) {
    return `aiplatform.${location}.rep.googleapis.com`;
  }
  return `${location}-aiplatform.googleapis.com`;
}

export function createGeminiClient(config: GeminiClientConfig): GeminiClient {
  const fetchFn = (input: string, init: RequestInit) => (config.fetch ?? globalThis.fetch)(input, init);
  const auth = config.auth ?? createMetadataAuth(config.fetch);

  return {
    async generateContent(model: string, body: unknown): Promise<Response> {
      if (config.backend === 'apikey') {
        return fetchFn(
          `${GEMINI_API_BASE}/v1beta/models/${model}:generateContent?key=${config.apiKey}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
          }
        );
      }

      const [project, accessToken] = await Promise.all([auth.getProjectId(), auth.getAccessToken()]);
      const location = config.vertexLocation;
      return fetchFn(
        `https://${vertexHost(location)}/v1/projects/${project}/locations/${location}/publishers/google/models/${model}:generateContent`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(body),
        }
      );
    },
  };
}
