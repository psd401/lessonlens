/**
 * Credentials for calling Google Cloud APIs as the Cloud Run runtime
 * service account. The access token and project ID come from the Cloud Run
 * metadata server, so no identifier lives in source.
 */

export interface GcpAuth {
  getProjectId(): Promise<string>;
  getAccessToken(): Promise<string>;
}

const METADATA_BASE = 'http://metadata.google.internal/computeMetadata/v1';
// Refresh the token this long before it expires
const TOKEN_REFRESH_MARGIN_MS = 60_000;

/**
 * fetchFn defaults to the global fetch at call time, so tests can replace
 * globalThis.fetch after this module is loaded.
 */
export function createMetadataAuth(fetchFn?: typeof fetch): GcpAuth {
  let projectId: string | undefined;
  let token: { value: string; expiresAt: number } | undefined;

  async function metadata(path: string): Promise<Response> {
    const response = await (fetchFn ?? globalThis.fetch)(`${METADATA_BASE}/${path}`, {
      headers: { 'Metadata-Flavor': 'Google' },
    });
    if (!response.ok) {
      throw new Error(`Metadata server returned ${response.status} for ${path}`);
    }
    return response;
  }

  return {
    async getProjectId(): Promise<string> {
      if (!projectId) {
        projectId = (await (await metadata('project/project-id')).text()).trim();
      }
      return projectId;
    },

    async getAccessToken(): Promise<string> {
      if (!token || Date.now() >= token.expiresAt - TOKEN_REFRESH_MARGIN_MS) {
        const body = await (await metadata('instance/service-accounts/default/token')).json() as {
          access_token: string;
          expires_in: number;
        };
        token = { value: body.access_token, expiresAt: Date.now() + body.expires_in * 1000 };
      }
      return token.value;
    },
  };
}
