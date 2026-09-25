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
