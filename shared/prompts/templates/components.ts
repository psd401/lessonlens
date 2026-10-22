/**
 * Shared prompt components used by both text and video analysis
 */

export const RATING_SCALE = `
## Rating Scale
Rate how fully the technique was carried out when it came up in this lesson, not how often it came up. A technique that came up once can earn any rating. The look-fors in each technique definition are the basis for the rating.
1 - Emerging: Attempted, with few look-fors present.
2 - Developing: Used with some look-fors present; key elements missing, or uneven when it came up more than once.
3 - Established: Used as intended, with most look-fors present.
4 - Refining: Used as intended, with attention to finer points such as timing, wording and follow-through.
5 - Extending: Used as intended and taken further: adapted to individual students, or students took it up themselves with little prompting.
`;

export const RESPONSE_SCHEMA_WITH_RATINGS = `
## Response Format
Provide your analysis as a JSON object with the following structure:
{
    "overallSummary": "2-3 sentence summary of what happened in the teaching session",
    "strengths": ["strength 1", "strength 2", "strength 3"],
    "growthAreas": ["growth area 1", "growth area 2"],
    "actionableNextSteps": ["specific action 1", "specific action 2", "specific action 3"],
    "techniqueEvaluations": [
        {
            "techniqueId": "exact-id-from-technique-definition",
            "wasObserved": true/false,
            "rating": 1-5 (null if not observed),
            "evidence": ["specific quote or behavior from transcript"],
            "feedback": "Detailed feedback about technique usage",
            "suggestions": ["specific improvement suggestion"]
        }
    ]
}
`;

export const RESPONSE_SCHEMA_WITHOUT_RATINGS = `
## Response Format
Provide your analysis as a JSON object with the following structure:
{
    "overallSummary": "2-3 sentence summary of what happened in the teaching session",
    "strengths": ["strength 1", "strength 2", "strength 3"],
    "growthAreas": ["growth area 1", "growth area 2"],
    "actionableNextSteps": ["specific action 1", "specific action 2", "specific action 3"],
    "techniqueEvaluations": [
        {
            "techniqueId": "exact-id-from-technique-definition",
            "wasObserved": true/false,
            "evidence": ["specific quote or behavior from transcript"],
            "feedback": "Detailed feedback about technique usage",
            "suggestions": ["specific improvement suggestion"]
        }
    ]
}
`;

export const GUIDELINES_BASE = `
## Guidelines
- IMPORTANT: Use the exact "ID" value shown for each technique as the "techniqueId" in your response
- Be specific and cite evidence from the transcript
- Provide actionable, growth-oriented feedback
- Balance recognition of strengths with constructive suggestions
{{ratingGuideline}}
- Focus on patterns rather than isolated instances
- Use warm, factual language grounded in evidence. Avoid superlatives (masterful, wonderful, amazing, incredible, fantastic, outstanding, brilliant, exceptional, perfect, extraordinary). Do not use exclamation points.

Respond ONLY with the JSON object, no additional text.`;

export const GUIDELINES_VIDEO_BASE = `
## Guidelines
- IMPORTANT: Use the exact "ID" value shown for each technique as the "techniqueId" in your response
- Be specific and cite observable evidence from the video (actions, quotes, interactions)
- Include timestamps when referencing specific moments if possible
- Consider both verbal and non-verbal teacher behaviors
- Provide actionable, growth-oriented feedback
- Balance recognition of strengths with constructive suggestions
{{ratingGuideline}}
- Focus on patterns rather than isolated instances
- Use warm, factual language grounded in evidence. Avoid superlatives (masterful, wonderful, amazing, incredible, fantastic, outstanding, brilliant, exceptional, perfect, extraordinary). Do not use exclamation points.

Respond ONLY with the JSON object, no additional text.`;

export const RATING_GUIDELINE_WITH = '- If a technique was not observed, including when the lesson gave no occasion for it, set wasObserved to false and rating to null';
export const RATING_GUIDELINE_WITHOUT = '- If a technique was not observed, including when the lesson gave no occasion for it, set wasObserved to false';
