/**
 * Prompt builder functions for LLM analysis
 */

import type { TechniqueDefinition, PauseData, TextAnalysisPromptOptions, VideoAnalysisPromptOptions, ChatPromptOptions } from './types';
import {
  RATING_SCALE,
  RESPONSE_SCHEMA_WITH_RATINGS,
  RESPONSE_SCHEMA_WITHOUT_RATINGS,
  GUIDELINES_BASE,
  GUIDELINES_VIDEO_BASE,
  RATING_GUIDELINE_WITH,
  RATING_GUIDELINE_WITHOUT,
} from './templates/components';
import {
  TEXT_ANALYSIS_SYSTEM,
  TEXT_ANALYSIS_TRANSCRIPT_SECTION,
  PAUSE_DATA_SECTION,
  TECHNIQUES_SECTION_HEADER,
} from './templates/text-analysis';
import {
  VIDEO_ANALYSIS_SYSTEM,
  VIDEO_TECHNIQUES_SECTION_HEADER,
} from './templates/video-analysis';
import {
  CHAT_SYSTEM_PROMPT,
  CHAT_CONTEXT_SECTION,
  CHAT_REFLECTION_SECTION,
  CHAT_REFLECTION_DATA_SECTION,
} from './templates/chat';

/**
 * Simple template processor for {{variable}} substitution.
 *
 * One pass with a function replacer: values are inserted literally (no
 * `$&`-style replacement patterns), and a value that itself contains
 * `{{otherKey}}` is not expanded again.
 */
function processTemplate(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (match, key: string) =>
    Object.hasOwn(vars, key) ? vars[key] : match
  );
}

/**
 * Removes any closing `</tag>` from content placed inside `<tag>` in a
 * template, so the content can't end its own data section early.
 */
function insideTag(tag: string, content: string): string {
  return content.replace(new RegExp(`<\\s*/\\s*${tag}\\s*>`, 'gi'), '');
}

/**
 * Format a single technique for inclusion in the prompt.
 *
 * Technique text comes from the client and is inlined as-is. The app only
 * sends its bundled frameworks, but an authenticated caller could send any
 * text here and steer the prompt (review finding SEC-06). Accepted on
 * purpose: the backend caps its size (CloudRunBackend/src/input-limits.ts),
 * replies go only to that caller, and a server-side allowlist would have to
 * change with every framework update in the app.
 */
function formatTechnique(technique: TechniqueDefinition): string {
  return `
### ${technique.name}
**ID:** ${technique.id}
**Description:** ${technique.description}

**Look-fors (observable indicators):**
${technique.lookFors.map(lf => `- ${lf}`).join('\n')}

**Exemplar phrases:**
${technique.exemplarPhrases.map(p => `- "${p}"`).join('\n')}
`;
}

/**
 * Format all techniques for inclusion in the prompt
 */
function formatTechniques(techniques: TechniqueDefinition[]): string {
  return techniques.map(formatTechnique).join('\n');
}

/**
 * Format pause data for inclusion in the prompt
 */
function formatPauseData(pauseData: PauseData): string {
  const pauseDetails = pauseData.pauses
    .map((p, i) => `${i + 1}. ${p.duration.toFixed(1)}s pause after "${p.precedingText}" → before "${p.followingText}"`)
    .join('\n');

  return processTemplate(PAUSE_DATA_SECTION, {
    pauseCount: pauseData.summary.count.toString(),
    pauseAvgDuration: pauseData.summary.averageDuration.toFixed(1),
    pauseMaxDuration: pauseData.summary.maxDuration.toFixed(1),
    pauseTotalTime: pauseData.summary.totalPauseTime.toFixed(1),
    pauseDetails: insideTag('pause_details', pauseDetails),
  });
}

/**
 * Build the complete text analysis prompt
 */
export function buildAnalysisPrompt(options: TextAnalysisPromptOptions): string {
  const { transcript, techniques, includeRatings, pauseData } = options;

  let prompt = TEXT_ANALYSIS_SYSTEM;

  // Add transcript section
  prompt += processTemplate(TEXT_ANALYSIS_TRANSCRIPT_SECTION, { transcript: insideTag('transcript', transcript) });

  // Add pause data section if provided and wait-time technique is selected
  if (pauseData && techniques.some(t => t.id === 'wait-time')) {
    prompt += formatPauseData(pauseData);
  }

  // Add techniques section
  prompt += TECHNIQUES_SECTION_HEADER;
  prompt += formatTechniques(techniques);

  // Add response schema
  prompt += includeRatings ? RESPONSE_SCHEMA_WITH_RATINGS : RESPONSE_SCHEMA_WITHOUT_RATINGS;

  // Add rating scale if ratings enabled
  if (includeRatings) {
    prompt += RATING_SCALE;
  }

  // Add guidelines
  const ratingGuideline = includeRatings ? RATING_GUIDELINE_WITH : RATING_GUIDELINE_WITHOUT;
  prompt += processTemplate(GUIDELINES_BASE, { ratingGuideline });

  return prompt;
}

/**
 * Build the complete video analysis prompt for Gemini
 */
export function buildVideoAnalysisPrompt(options: VideoAnalysisPromptOptions): string {
  const { techniques, includeRatings } = options;

  let prompt = VIDEO_ANALYSIS_SYSTEM;

  // Add techniques section
  prompt += VIDEO_TECHNIQUES_SECTION_HEADER;
  prompt += formatTechniques(techniques);

  // Add response schema
  prompt += includeRatings ? RESPONSE_SCHEMA_WITH_RATINGS : RESPONSE_SCHEMA_WITHOUT_RATINGS;

  // Add rating scale if ratings enabled
  if (includeRatings) {
    prompt += RATING_SCALE;
  }

  // Add guidelines
  const ratingGuideline = includeRatings ? RATING_GUIDELINE_WITH : RATING_GUIDELINE_WITHOUT;
  prompt += processTemplate(GUIDELINES_VIDEO_BASE, { ratingGuideline });

  return prompt;
}

/**
 * Build the chat system prompt with context
 */
export function buildChatPrompt(options: ChatPromptOptions): {
  systemPrompt: string;
  messages: Array<{ role: string; content: string }>;
} {
  const {
    transcript,
    analysisSummary,
    techniqueEvaluationsSummary,
    reflectionSummary,
    messages,
    techniqueNames,
  } = options;

  // Build system prompt
  let systemPrompt = processTemplate(CHAT_SYSTEM_PROMPT, {
    techniqueNames: techniqueNames.join(', '),
  });

  // Add context section
  systemPrompt += processTemplate(CHAT_CONTEXT_SECTION, {
    transcript: insideTag('transcript', transcript),
    analysisSummary: insideTag('analysis_summary', analysisSummary),
    techniqueEvaluationsSummary: insideTag('technique_evaluations', techniqueEvaluationsSummary ?? ''),
  });

  // Add reflection context if available (the app sends it pre-formatted)
  if (reflectionSummary) {
    systemPrompt += processTemplate(CHAT_REFLECTION_DATA_SECTION, {
      reflectionSummary: insideTag('teacher_reflection', reflectionSummary.trim()),
    });
  }

  // Convert messages to Gemini format
  const formattedMessages = messages.map(m => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    content: m.content,
  }));

  return { systemPrompt, messages: formattedMessages };
}
