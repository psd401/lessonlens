/**
 * Shared prompt components used by both text and video analysis
 */

export const RATING_SCALE = `
## Rating Scale
1 - Developing: Technique not observed or needs significant development
2 - Emerging: Beginning to implement technique with inconsistent results
3 - Proficient: Solid implementation of technique with room for refinement
4 - Accomplished: Effective and consistent use of technique
5 - Exemplary: Strong, consistent implementation that could serve as a model
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

export const RATING_GUIDELINE_WITH = '- If a technique was not observed, set wasObserved to false and rating to null';
export const RATING_GUIDELINE_WITHOUT = '- If a technique was not observed, set wasObserved to false';
