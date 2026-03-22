import { Hono } from 'hono';
import { verifySession } from './auth';
import { env, checkRateLimit, getRateLimitStatus } from '../index';
import { buildAnalysisPrompt, type TechniqueDefinition, type PauseData, type GeminiGenerateResponse } from '../../../shared/prompts';

export const analyzeRoutes = new Hono();

interface AnalyzeRequest {
  transcript: string;
  techniques: TechniqueDefinition[];
  includeRatings?: boolean;
  pauseData?: PauseData;
}

const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com';

/**
 * POST /analyze
 * Proxies analysis request to Gemini API with rate limiting
 */
analyzeRoutes.post('/', async (c) => {
  // Verify authentication
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  const userId = authResult.userId!;

  // Check rate limit
  const rateLimitKey = `rate:text:${userId}`;
  const rateCheck = checkRateLimit(rateLimitKey, env.RATE_LIMIT_PER_HOUR);

  if (!rateCheck.allowed) {
    return c.json({
      error: 'Rate limit exceeded',
      message: `Maximum ${env.RATE_LIMIT_PER_HOUR} analyses per hour. Please try again later.`,
      retry_after: rateCheck.resetIn,
    }, 429);
  }

  // Parse request
  let body: AnalyzeRequest;
  try {
    body = await c.req.json<AnalyzeRequest>();
  } catch (err) {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { transcript, techniques, includeRatings = true, pauseData } = body;

  if (!transcript || !techniques || techniques.length === 0) {
    return c.json({ error: 'Missing transcript or techniques' }, 400);
  }

  // Input size validation to prevent DoS and excessive API costs
  const MAX_TRANSCRIPT_LENGTH = 100000; // ~100KB of text
  const MAX_TECHNIQUES = 20;
  const MAX_PAUSES = 100;

  if (transcript.length > MAX_TRANSCRIPT_LENGTH) {
    return c.json({ error: 'Transcript too large', maxLength: MAX_TRANSCRIPT_LENGTH }, 400);
  }

  if (techniques.length > MAX_TECHNIQUES) {
    return c.json({ error: 'Too many techniques', maxTechniques: MAX_TECHNIQUES }, 400);
  }

  if (pauseData?.pauses && pauseData.pauses.length > MAX_PAUSES) {
    return c.json({ error: 'Too many pauses', maxPauses: MAX_PAUSES }, 400);
  }

  // Build the analysis prompt
  const prompt = buildAnalysisPrompt({ transcript, techniques, includeRatings, pauseData });

  const model = env.GEMINI_TEXT_MODEL;

  // Call Gemini API
  try {
    const response = await fetch(
      `${GEMINI_API_BASE}/v1beta/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          contents: [
            {
              parts: [{ text: prompt }],
            },
          ],
          generationConfig: {
            temperature: 0.4,
            maxOutputTokens: 8192,
            responseMimeType: 'application/json',
          },
        }),
      }
    );

    if (!response.ok) {
      console.error('Gemini API error:', response.status);
      return c.json({
        error: 'Analysis service error',
        status: response.status,
      }, 502);
    }

    const geminiResponse = await response.json() as GeminiGenerateResponse;

    // Check if Gemini returned candidates (may be blocked by safety filters)
    if (!geminiResponse.candidates || geminiResponse.candidates.length === 0) {
      console.error('Gemini returned no candidates:', JSON.stringify(geminiResponse, null, 2));
      const blockReason = (geminiResponse as any).promptFeedback?.blockReason;
      return c.json({
        error: 'Analysis blocked or failed',
        message: blockReason ? 'Content was blocked by safety filters' : 'Analysis service returned no results'
      }, 502);
    }

    // Extract the JSON response from Gemini
    const analysisText = geminiResponse.candidates[0]?.content?.parts[0]?.text;

    if (!analysisText) {
      console.error('Gemini candidate has no text content');
      return c.json({ error: 'Empty response from analysis service' }, 502);
    }

    // Parse Gemini's JSON response
    let analysisResult;
    try {
      // Try to extract JSON from the response (handle potential markdown code blocks)
      let jsonText = analysisText;
      const jsonMatch = analysisText.match(/```json\s*([\s\S]*?)\s*```/);
      if (jsonMatch) {
        jsonText = jsonMatch[1];
      }
      analysisResult = JSON.parse(jsonText);
    } catch (parseErr) {
      // Log error details server-side only (redact transcript content)
      console.error('Failed to parse Gemini response:', parseErr);
      console.error('Response length:', analysisText.length);
      return c.json({
        error: 'Invalid response format from analysis service'
      }, 502);
    }

    // Return formatted response
    return c.json({
      overall_summary: analysisResult.overallSummary,
      strengths: analysisResult.strengths || [],
      growth_areas: analysisResult.growthAreas || [],
      actionable_next_steps: analysisResult.actionableNextSteps || [],
      technique_evaluations: (analysisResult.techniqueEvaluations || []).map((te: any) => ({
        technique_id: te.techniqueId,
        was_observed: te.wasObserved,
        rating: te.rating,
        evidence: te.evidence || [],
        feedback: te.feedback,
        suggestions: te.suggestions || [],
      })),
      model_used: model,
      usage: {
        input_tokens: geminiResponse.usageMetadata?.promptTokenCount,
        output_tokens: geminiResponse.usageMetadata?.candidatesTokenCount,
      },
    });

  } catch (err) {
    console.error('Analysis request failed:', err);
    return c.json({
      error: 'Analysis request failed'
    }, 500);
  }
});

/**
 * GET /analyze/rate-limit
 * Returns current rate limit status for the user
 */
analyzeRoutes.get('/rate-limit', async (c) => {
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  const userId = authResult.userId!;
  const rateLimitKey = `rate:text:${userId}`;
  const status = getRateLimitStatus(rateLimitKey, env.RATE_LIMIT_PER_HOUR);

  return c.json(status);
});
