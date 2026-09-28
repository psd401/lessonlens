/**
 * Sends generateContent requests to Gemini through one of two backends:
 *
 * - "apikey": the Gemini Developer API (generativelanguage.googleapis.com)
 *   with GEMINI_API_KEY. Kept as a manual fallback during the Vertex move.
 * - "vertex": Vertex AI in the Cloud Run project, authenticated as the
 *   service's runtime service account. The access token and project ID come
 *   from the Cloud Run metadata server, so no identifier lives in source.
 *
 * Both backends take the same request body and return the same response and
 * error shapes, so callers handle either one identically.
 */

export type GeminiBackend = 'apikey' | 'vertex';

export interface GeminiClientConfig {
  backend: GeminiBackend;
  apiKey: string;
  vertexLocation: string;
  fetch?: typeof fetch;
}

export interface GeminiClient {
  generateContent(model: string, body: unknown): Promise<Response>;
}

const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com';
const METADATA_BASE = 'http://metadata.google.internal/computeMetadata/v1';
// Refresh the token this long before it expires
const TOKEN_REFRESH_MARGIN_MS = 60_000;

export function parseGeminiBackend(value: string | undefined): GeminiBackend {
  const backend = value || 'apikey';
  if (backend !== 'apikey' && backend !== 'vertex') {
    throw new Error(`GEMINI_BACKEND must be "apikey" or "vertex", got "${backend}"`);
  }
  return backend;
}

export function vertexHost(location: string): string {
  return location === 'global'
    ? 'aiplatform.googleapis.com'
    : `${location}-aiplatform.googleapis.com`;
}

export function createGeminiClient(config: GeminiClientConfig): GeminiClient {
  const fetchFn = config.fetch ?? fetch;

  let projectId: string | undefined;
  let token: { value: string; expiresAt: number } | undefined;

  async function metadata(path: string): Promise<Response> {
    const response = await fetchFn(`${METADATA_BASE}/${path}`, {
      headers: { 'Metadata-Flavor': 'Google' },
    });
    if (!response.ok) {
      throw new Error(`Metadata server returned ${response.status} for ${path}`);
    }
    return response;
  }

  async function getProjectId(): Promise<string> {
    if (!projectId) {
      projectId = (await (await metadata('project/project-id')).text()).trim();
    }
    return projectId;
  }

  async function getAccessToken(): Promise<string> {
    if (!token || Date.now() >= token.expiresAt - TOKEN_REFRESH_MARGIN_MS) {
      const body = await (await metadata('instance/service-accounts/default/token')).json() as {
        access_token: string;
        expires_in: number;
      };
      token = { value: body.access_token, expiresAt: Date.now() + body.expires_in * 1000 };
    }
    return token.value;
  }

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

      const [project, accessToken] = await Promise.all([getProjectId(), getAccessToken()]);
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
