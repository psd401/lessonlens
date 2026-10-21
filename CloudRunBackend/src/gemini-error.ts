/**
 * Logs a failed Gemini response and returns the status for the client.
 *
 * Logs only Gemini's enum-style fields (error.status and ErrorInfo reasons),
 * never error.message or the raw body, which can echo transcript content.
 */
export async function describeGeminiError(response: Response): Promise<{ status: number }> {
  let geminiStatus: string | undefined;
  let reasons: string[] = [];
  try {
    const body = await response.json() as {
      error?: { status?: string; details?: { reason?: string }[] };
    };
    geminiStatus = body.error?.status;
    reasons = (body.error?.details ?? [])
      .map((d) => d.reason)
      .filter((r): r is string => typeof r === 'string');
  } catch {
    // Non-JSON body; status code alone is logged
  }

  console.error('Gemini API error:', response.status, geminiStatus ?? '', reasons.join(','));

  return { status: response.status };
}

/** Gemini's finishReason and blockReason values are enums such as SAFETY. */
const ENUM_VALUE = /^[A-Z_]{1,40}$/;
const enumOrEmpty = (value: unknown) => (typeof value === 'string' && ENUM_VALUE.test(value) ? value : '');

/**
 * Logs why a Gemini reply had no usable text. Same rule as
 * describeGeminiError: counts and enum fields only, never the reply itself,
 * which can quote the transcript.
 */
export function logUnusableGeminiResponse(label: string, response: unknown): void {
  const r = (response ?? {}) as {
    candidates?: { finishReason?: unknown }[];
    promptFeedback?: { blockReason?: unknown };
  };
  const candidates = Array.isArray(r.candidates) ? r.candidates : [];
  console.error(
    `${label}:`,
    `candidates=${candidates.length}`,
    `finishReason=${candidates.map((c) => enumOrEmpty(c?.finishReason)).join(',')}`,
    `blockReason=${enumOrEmpty(r.promptFeedback?.blockReason)}`
  );
}

/**
 * Logs a failed JSON.parse of Gemini's reply. The error's message can quote
 * part of the reply, so only its name and the reply length are logged.
 */
export function logUnparseableGeminiText(err: unknown, textLength: number): void {
  const name = err instanceof Error ? err.name : 'UnknownError';
  console.error('Failed to parse Gemini response:', name, `length=${textLength}`);
}
