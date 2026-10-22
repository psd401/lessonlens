/**
 * Per-field size caps for user content that goes into Gemini prompts
 * (review finding SEC-05). The routes already cap counts (techniques,
 * pauses, messages); these cap the strings inside them, so one request
 * can't run up the district's Gemini bill.
 *
 * Sized against what the app actually sends (October 2026):
 * - Bundled techniques (58 across 7 frameworks): name <= 34 chars,
 *   description <= 434, <= 6 look-fors / exemplar phrases of <= 108 chars.
 * - Pause text is the last/next 5 words around a pause.
 * - Assistant chat replies are capped at 2048 output tokens (~8-10k chars),
 *   and the whole history is resent each turn, so message caps must fit them.
 * - Analysis replies are capped at 8192 output tokens (~32k chars), which
 *   bounds analysis_summary and technique_evaluations_summary.
 *
 * Largest possible prompt per request at these caps:
 * - /analyze: 100k transcript + 20 x 8.9k techniques + 100 x 600 pause text ≈ 340k chars
 * - /analyze/video: 20 x 8.9k techniques ≈ 180k chars (plus the video)
 * - /chat: 100k transcript + 100k summaries + 2k names + 50 x 16k messages ≈ 1M chars
 *
 * Requests over a cap are rejected, never truncated: a silently cut
 * transcript or technique would corrupt the analysis.
 */
import type { ChatMessage, PauseData, TechniqueDefinition } from '../../shared/prompts';

export const LIMITS = {
  techniqueId: 100,
  techniqueName: 100,
  techniqueDescription: 1_500,
  techniqueListItems: 12,
  techniqueListItem: 300,
  pauseText: 300,
  chatMessage: 16_000,
  analysisSummary: 40_000,
  techniqueEvaluationsSummary: 40_000,
  reflectionSummary: 20_000,
  techniqueNames: 20,
  techniqueNameEntry: 100,
} as const;

/** Total request body cap for /analyze and /chat; the field caps above total well under this. */
export const MAX_BODY_BYTES = 2 * 1024 * 1024;

/** Error body in the routes' existing shape, or null when the input fits. */
export type LimitError = { error: string; field: string; maxLength?: number; maxItems?: number };

function checkString(value: unknown, field: string, maxLength: number, optional = false): LimitError | null {
  if (value === undefined || value === null) {
    return optional ? null : { error: 'Missing field', field };
  }
  if (typeof value !== 'string') {
    return { error: 'Field must be a string', field };
  }
  if (value.length > maxLength) {
    return { error: 'Field too large', field, maxLength };
  }
  return null;
}

function checkStringList(value: unknown, field: string, maxItems: number, maxLength: number): LimitError | null {
  if (!Array.isArray(value)) {
    return { error: 'Field must be a list', field };
  }
  if (value.length > maxItems) {
    return { error: 'Too many items', field, maxItems };
  }
  for (let i = 0; i < value.length; i++) {
    const err = checkString(value[i], `${field}[${i}]`, maxLength);
    if (err) return err;
  }
  return null;
}

export function checkTechniques(techniques: TechniqueDefinition[]): LimitError | null {
  for (let i = 0; i < techniques.length; i++) {
    const t = techniques[i] ?? ({} as TechniqueDefinition);
    const at = `techniques[${i}]`;
    const err =
      checkString(t.id, `${at}.id`, LIMITS.techniqueId) ??
      checkString(t.name, `${at}.name`, LIMITS.techniqueName) ??
      checkString(t.description, `${at}.description`, LIMITS.techniqueDescription) ??
      checkStringList(t.lookFors, `${at}.lookFors`, LIMITS.techniqueListItems, LIMITS.techniqueListItem) ??
      checkStringList(t.exemplarPhrases, `${at}.exemplarPhrases`, LIMITS.techniqueListItems, LIMITS.techniqueListItem);
    if (err) return err;
  }
  return null;
}

export function checkPauseText(pauseData: PauseData | undefined): LimitError | null {
  const pauses = pauseData?.pauses ?? [];
  for (let i = 0; i < pauses.length; i++) {
    const at = `pauseData.pauses[${i}]`;
    const err =
      checkString(pauses[i]?.precedingText, `${at}.precedingText`, LIMITS.pauseText) ??
      checkString(pauses[i]?.followingText, `${at}.followingText`, LIMITS.pauseText);
    if (err) return err;
  }
  return null;
}

export function checkChatFields(fields: {
  analysis_summary: unknown;
  technique_evaluations_summary: unknown;
  reflection_summary?: unknown;
  messages: ChatMessage[];
  technique_names: unknown;
}): LimitError | null {
  const fieldErr =
    checkString(fields.analysis_summary, 'analysis_summary', LIMITS.analysisSummary) ??
    checkString(fields.technique_evaluations_summary, 'technique_evaluations_summary', LIMITS.techniqueEvaluationsSummary, true) ??
    checkString(fields.reflection_summary, 'reflection_summary', LIMITS.reflectionSummary, true) ??
    checkStringList(fields.technique_names, 'technique_names', LIMITS.techniqueNames, LIMITS.techniqueNameEntry);
  if (fieldErr) return fieldErr;

  for (let i = 0; i < fields.messages.length; i++) {
    const err = checkString(fields.messages[i]?.content, `messages[${i}].content`, LIMITS.chatMessage);
    if (err) return err;
  }
  return null;
}
