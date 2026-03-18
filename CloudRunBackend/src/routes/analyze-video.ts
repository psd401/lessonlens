import { Hono } from 'hono';
import { verifySession } from './auth';
import { env, checkRateLimit, getRateLimitStatus } from '../index';
import { buildVideoAnalysisPrompt, type TechniqueDefinition, type GeminiGenerateResponse } from '../../../shared/prompts';

export const analyzeVideoRoutes = new Hono();

interface AnalyzeVideoRequest {
  geminiFileName: string;  // e.g., "files/abc123"
  techniques: TechniqueDefinition[];
  includeRatings?: boolean;
}

interface GeminiFileStatusResponse {
  name: string;
  displayName: string;
  mimeType: string;
  sizeBytes: string;
  createTime: string;
  updateTime: string;
  expirationTime: string;
  sha256Hash: string;
  uri: string;
  state: 'PROCESSING' | 'ACTIVE' | 'FAILED';
}

const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com';
const FILE_PROCESSING_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutes (Cloud Run allows longer)
const FILE_PROCESSING_POLL_INTERVAL_MS = 5000; // 5 seconds

// Gemini file names follow pattern: files/<alphanumeric-id>
const GEMINI_FILE_NAME_PATTERN = /^files\/[a-zA-Z0-9_-]+$/;

/**
 * POST /analyze/video
 * Analyze a video that has been uploaded to Gemini
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

  const { geminiFileName, techniques, includeRatings = true } = body;

  if (!geminiFileName || !techniques || techniques.length === 0) {
    return c.json({ error: 'Missing geminiFileName or techniques' }, 400);
  }

  // Validate geminiFileName format to prevent path traversal
  if (!GEMINI_FILE_NAME_PATTERN.test(geminiFileName)) {
    return c.json({ error: 'Invalid geminiFileName format' }, 400);
  }

  // Input size validation to prevent DoS and excessive API costs
  const MAX_TECHNIQUES = 20;

  if (techniques.length > MAX_TECHNIQUES) {
    return c.json({ error: 'Too many techniques', maxTechniques: MAX_TECHNIQUES }, 400);
  }

  try {
    // 1. Wait for Gemini file processing to complete
    const processedFile = await waitForFileProcessing(
      geminiFileName,
      env.GEMINI_API_KEY
    );

    if (processedFile.state !== 'ACTIVE') {
      throw new Error(`File processing failed: ${processedFile.state}`);
    }

    // 2. Call Gemini with video and prompt
    const prompt = buildVideoAnalysisPrompt({ techniques, includeRatings });
    const geminiResponse = await callGeminiWithVideo(
      processedFile.uri,
      processedFile.mimeType,
      prompt,
      env.GEMINI_VIDEO_MODEL,
      env.GEMINI_API_KEY
    );

    // 3. Parse response
    // Check if Gemini returned candidates (may be blocked by safety filters)
    if (!geminiResponse.candidates || geminiResponse.candidates.length === 0) {
      console.error('Gemini returned no candidates:', JSON.stringify(geminiResponse, null, 2));
      const blockReason = (geminiResponse as any).promptFeedback?.blockReason;
      return c.json({
        error: 'Video analysis blocked or failed',
        message: blockReason ? 'Content was blocked by safety filters' : 'Analysis service returned no results'
      }, 502);
    }

    const analysisText = geminiResponse.candidates[0]?.content?.parts[0]?.text;

    if (!analysisText) {
      console.error('Gemini candidate has no text content');
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
      console.error('Failed to parse Gemini response:', parseErr);
      console.error('Response length:', analysisText.length);
      return c.json({
        error: 'Invalid response format from analysis service'
      }, 502);
    }

    // 4. Cleanup: delete from Gemini (best effort)
    await deleteGeminiFile(geminiFileName, env.GEMINI_API_KEY).catch(() => {});

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

  } catch (err) {
    console.error('Video analysis failed:', err);

    // Cleanup on error (best effort)
    await deleteGeminiFile(geminiFileName, env.GEMINI_API_KEY).catch(() => {});

    return c.json({
      error: 'Video analysis failed'
    }, 500);
  }
});

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

/**
 * Poll Gemini File API until file is processed
 */
async function waitForFileProcessing(
  fileName: string,
  apiKey: string
): Promise<GeminiFileStatusResponse> {
  const startTime = Date.now();

  while (Date.now() - startTime < FILE_PROCESSING_TIMEOUT_MS) {
    const response = await fetch(
      `${GEMINI_API_BASE}/v1beta/${fileName}?key=${apiKey}`
    );

    if (!response.ok) {
      throw new Error(`Failed to check file status: ${response.status}`);
    }

    const fileStatus = await response.json() as GeminiFileStatusResponse;

    if (fileStatus.state === 'ACTIVE') {
      return fileStatus;
    }

    if (fileStatus.state === 'FAILED') {
      throw new Error('File processing failed');
    }

    // Wait before polling again
    await new Promise(resolve => setTimeout(resolve, FILE_PROCESSING_POLL_INTERVAL_MS));
  }

  throw new Error('File processing timed out');
}

/**
 * Call Gemini API with video and prompt
 */
async function callGeminiWithVideo(
  fileUri: string,
  mimeType: string,
  prompt: string,
  model: string,
  apiKey: string
): Promise<GeminiGenerateResponse> {
  const response = await fetch(
    `${GEMINI_API_BASE}/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                fileData: {
                  mimeType,
                  fileUri,
                },
              },
              {
                text: prompt,
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.4,
          maxOutputTokens: 8192,
        },
      }),
    }
  );

  if (!response.ok) {
    throw new Error(`Gemini API error: ${response.status}`);
  }

  return response.json() as Promise<GeminiGenerateResponse>;
}

/**
 * Delete a file from Gemini File API
 */
async function deleteGeminiFile(fileName: string, apiKey: string): Promise<void> {
  const response = await fetch(
    `${GEMINI_API_BASE}/v1beta/${fileName}?key=${apiKey}`,
    { method: 'DELETE' }
  );

  if (!response.ok && response.status !== 404) {
    console.error('Failed to delete Gemini file:', response.status);
  }
}
