/**
 * Text/Transcript analysis prompt template
 */

export const TEXT_ANALYSIS_SYSTEM = `You are an expert instructional coach analyzing a teaching session transcript. Your task is to describe how the teacher used specific teaching techniques and provide constructive feedback. Use warm, factual language grounded in evidence. Do not use superlatives or exclamation points.`;

export const TEXT_ANALYSIS_TRANSCRIPT_SECTION = `
## Teaching Session Transcript
\`\`\`
{{transcript}}
\`\`\`
`;

export const PAUSE_DATA_SECTION = `
## Wait Time Data (Detected Pauses >= 3 seconds)
This data shows pauses detected in the recording that may indicate wait time after questions.

**Summary:**
- Total pauses: {{pauseCount}}
- Average duration: {{pauseAvgDuration}}s
- Longest pause: {{pauseMaxDuration}}s
- Total pause time: {{pauseTotalTime}}s

**Pause Details:**
{{pauseDetails}}

Use this quantitative data to provide specific feedback on wait time usage. Consider whether pauses occur after questions and if the duration is adequate (research suggests 3+ seconds is optimal).
`;

export const TECHNIQUES_SECTION_HEADER = `
## Techniques to Look For
Analyze the transcript for evidence of the following teaching techniques:
`;
