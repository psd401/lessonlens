import { Hono } from 'hono';
import { verifySession } from './auth';
import { describeGeminiError, logUnusableGeminiResponse, logUnparseableGeminiText, readGeminiJson } from '../gemini-error';
import { VIDEO_EXTENSIONS } from '../video-storage';
import { checkTechniques } from '../input-limits';
import { env, gemini, videoStorage, checkRateLimit, getRateLimitStatus } from '../index';
import { buildVideoAnalysisPrompt, type TechniqueDefinition, type GeminiGenerateResponse } from '../../../shared/prompts';
import type { Context } from 'hono';

export const analyzeVideoRoutes = new Hono();

interface AnalyzeVideoRequest {
  gcsObject: string;        // from /upload/initiate/gcs; analyzed on Vertex AI
  techniques: TechniqueDefinition[];
  includeRatings?: boolean;
  durationSeconds?: number; // video length from the app, used to lower the frame rate for long lessons
}

// Past this length, sample 0.5 frames per second instead of Vertex's default
// 1: about a third fewer input tokens for a mostly static classroom video,
// and faster. Google suggests under 1 fps for long, mostly static videos
// such as lectures.
export const LONG_VIDEO_SECONDS = 45 * 60;
export const LONG_VIDEO_FPS = 0.5;

/** videoMetadata for the Vertex fileData part, or undefined for the default */
export function videoMetadataFor(durationSeconds: unknown): { fps: number } | undefined {
  return typeof durationSeconds === 'number' && Number.isFinite(durationSeconds) && durationSeconds > LONG_VIDEO_SECONDS
    ? { fps: LONG_VIDEO_FPS }
    : undefined;
}

/**
 * POST /analyze/video
 * Analyze a video uploaded to Cloud Storage (gcsObject), on Vertex AI.
 */
analyzeVideoRoutes.post('/', async (c) => {
  // Verify authentication
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  const userId = authResult.userId!;

  // Check video-specific rate limit (separate from text analysis)
  const rateLimitKey = `rate:video:${userId}`;
  const rateCheck = checkRateLimit(rateLimitKey, env.VIDEO_RATE_LIMIT_PER_HOUR);

  if (!rateCheck.allowed) {
    return c.json({
      error: 'Rate limit exceeded',
      message: `Maximum ${env.VIDEO_RATE_LIMIT_PER_HOUR} video analyses per hour. Please try again later.`,
      retry_after: rateCheck.resetIn,
    }, 429);
  }

  // Parse request
  let body: AnalyzeVideoRequest;
  try {
    body = await c.req.json<AnalyzeVideoRequest>();
  } catch (err) {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { gcsObject, techniques, includeRatings = true, durationSeconds } = body;

  if (!gcsObject || !techniques || techniques.length === 0) {
    return c.json({ error: 'Missing gcsObject or techniques' }, 400);
  }

  if (!videoStorage) {
    return c.json({ error: 'Video upload is not configured' }, 503);
  }
  // Only the uploader's own objects; also rules out path tricks, since the
  // name must match uploads/<caller's folder>/<uuid>.<ext> exactly
  if (!videoStorage.isOwnedBy(userId, gcsObject)) {
    return c.json({ error: 'Upload not found' }, 404);
  }

  // Input size validation to prevent DoS and excessive API costs
  const MAX_TECHNIQUES = 20;

  if (techniques.length > MAX_TECHNIQUES) {
    return c.json({ error: 'Too many techniques', maxTechniques: MAX_TECHNIQUES }, 400);
  }

  const limitError = checkTechniques(techniques);
  if (limitError) {
    return c.json(limitError, 400);
  }

  return analyzeFromCloudStorage(c, gcsObject, techniques, includeRatings, durationSeconds);
});

/**
 * Cloud Storage path: send the gs:// URI to Vertex AI, then delete the object
 * whether analysis succeeded or failed (the bucket's lifecycle rule is only a
 * backstop).
 */
async function analyzeFromCloudStorage(
  c: Context,
  gcsObject: string,
  techniques: TechniqueDefinition[],
  includeRatings: boolean,
  durationSeconds?: number
) {
  const storage = videoStorage!;
  try {
    const object = await storage.getObject(gcsObject);
    if (!object) {
      return c.json({ error: 'Upload not found' }, 404);
    }
    if (!VIDEO_EXTENSIONS[object.contentType]) {
      return c.json({ error: 'Unsupported video type' }, 400);
    }

    const prompt = buildVideoAnalysisPrompt({ techniques, includeRatings });
    const response = await gemini.generateContent(env.GEMINI_VIDEO_MODEL, {
      contents: [
        {
          role: 'user',
          parts: [
            {
              fileData: { mimeType: object.contentType, fileUri: storage.gsUri(gcsObject) },
              ...(videoMetadataFor(durationSeconds) && { videoMetadata: videoMetadataFor(durationSeconds) }),
            },
            { text: prompt },
          ],
        },
      ],
      generationConfig: {
        temperature: 0.4,
        maxOutputTokens: 8192,
        responseMimeType: 'application/json',
      },
    });

    if (!response.ok) {
      // A 400 here usually means Vertex rejected the video itself (for
      // example longer than the model accepts); the app shows remediation
      return c.json({
        error: 'Video analysis service error',
        ...(await describeGeminiError(response)),
      }, 502);
    }

    return formatVideoAnalysis(c, await readGeminiJson<GeminiGenerateResponse>(response));
  } catch (err) {
    console.error('Video analysis failed:', err);
    return c.json({ error: 'Video analysis failed' }, 500);
  } finally {
    await storage.deleteObject(gcsObject).catch((err) => {
      console.error('Failed to delete uploaded video:', err);
    });
  }
}

/**
 * Turns Gemini's JSON reply into the app's analysis response (same structure
 * as text analysis).
 */
function formatVideoAnalysis(c: Context, geminiResponse: GeminiGenerateResponse | null) {
  // Null when the envelope wasn't JSON; readGeminiJson has already logged it
  if (!geminiResponse) {
    return c.json({ error: 'Invalid response format from analysis service' }, 502);
  }

  // Check if Gemini returned candidates (may be blocked by safety filters)
  if (!geminiResponse.candidates || geminiResponse.candidates.length === 0) {
    logUnusableGeminiResponse('Gemini returned no candidates', geminiResponse);
    const blockReason = (geminiResponse as any).promptFeedback?.blockReason;
    return c.json({
      error: 'Video analysis blocked or failed',
      message: blockReason ? 'Content was blocked by safety filters' : 'Analysis service returned no results'
    }, 502);
  }

  const analysisText = geminiResponse.candidates[0]?.content?.parts[0]?.text;

  if (!analysisText) {
    logUnusableGeminiResponse('Gemini candidate has no text content', geminiResponse);
    return c.json({ error: 'Empty response from analysis service' }, 502);
  }

  let analysisResult;
  try {
    let jsonText = analysisText;
    const jsonMatch = analysisText.match(/```json\s*([\s\S]*?)\s*```/);
    if (jsonMatch) {
      jsonText = jsonMatch[1];
    }
    analysisResult = JSON.parse(jsonText);
  } catch (parseErr) {
    // Log error details server-side only (avoid logging video analysis content)
    logUnparseableGeminiText(parseErr, analysisText.length);
    return c.json({
      error: 'Invalid response format from analysis service'
    }, 502);
  }

  // Return formatted response (same structure as text analysis)
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
    model_used: env.GEMINI_VIDEO_MODEL,
    usage: {
      input_tokens: geminiResponse.usageMetadata?.promptTokenCount,
      output_tokens: geminiResponse.usageMetadata?.candidatesTokenCount,
    },
  });
}

/**
 * GET /analyze/video/rate-limit
 * Returns current video rate limit status for the user
 */
analyzeVideoRoutes.get('/rate-limit', async (c) => {
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  const userId = authResult.userId!;
  const rateLimitKey = `rate:video:${userId}`;
  const status = getRateLimitStatus(rateLimitKey, env.VIDEO_RATE_LIMIT_PER_HOUR);

  return c.json(status);
});
