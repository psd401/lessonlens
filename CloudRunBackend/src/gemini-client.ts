/**
 * Sends generateContent requests to Gemini on Vertex AI in the Cloud Run
 * project, authenticated as the service's runtime service account (see
 * gcp-auth.ts). The older Gemini Developer API (API key) path was retired
 * in October 2026.
 */

import { createMetadataAuth, type GcpAuth } from './gcp-auth';

export interface GeminiClientConfig {
  vertexLocation: string;
  auth?: GcpAuth;
  fetch?: typeof fetch;
}

export interface GeminiClient {
  generateContent(model: string, body: unknown): Promise<Response>;
}

// Multi-region locations use their own hostnames; they keep ML processing
// inside that jurisdiction (the global endpoint does not)
const MULTI_REGION_LOCATIONS = new Set(['us', 'eu']);

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
