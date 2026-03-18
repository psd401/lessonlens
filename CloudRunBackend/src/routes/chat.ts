import { Hono } from 'hono';
import { verifySession } from './auth';
import { env, checkRateLimit, getRateLimitStatus } from '../index';
import { buildChatPrompt, type ChatMessage, type GeminiGenerateResponse } from '../../../shared/prompts';

export const chatRoutes = new Hono();

interface ChatRequest {
  transcript: string;
  analysis_summary: string;
  technique_evaluations_summary: string;
  reflection_summary?: string;
  messages: ChatMessage[];
  technique_names: string[];
}

const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com';

/**
 * POST /chat
 * Interactive coaching chat with full session context
 */
chatRoutes.post('/', async (c) => {
  // Verify authentication
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  const userId = authResult.userId!;

  // Check rate limit (separate from analysis rate limit)
  const chatLimit = env.CHAT_RATE_LIMIT_PER_HOUR;
  const rateLimitKey = `rate:chat:${userId}`;
  const rateCheck = checkRateLimit(rateLimitKey, chatLimit);

  if (!rateCheck.allowed) {
    return c.json({
      error: 'Rate limit exceeded',
      message: `Maximum ${chatLimit} chat messages per hour. Please try again later.`,
      retry_after: rateCheck.resetIn,
    }, 429);
  }

  // Parse request
  let body: ChatRequest;
  try {
    body = await c.req.json<ChatRequest>();
  } catch (err) {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { transcript, analysis_summary, technique_evaluations_summary, reflection_summary, messages, technique_names } = body;

  if (!transcript || !analysis_summary || !messages || messages.length === 0) {
    return c.json({ error: 'Missing required fields: transcript, analysis_summary, messages' }, 400);
  }

  if (!technique_names || technique_names.length === 0) {
    return c.json({ error: 'Missing technique_names' }, 400);
  }

  // Input validation
  const MAX_TRANSCRIPT_LENGTH = 100000;
  const MAX_MESSAGES = 50;

  if (transcript.length > MAX_TRANSCRIPT_LENGTH) {
    return c.json({ error: 'Transcript too large', maxLength: MAX_TRANSCRIPT_LENGTH }, 400);
  }

  if (messages.length > MAX_MESSAGES) {
    return c.json({ error: 'Too many messages', maxMessages: MAX_MESSAGES }, 400);
  }

  // Build chat prompt
  const { systemPrompt, messages: formattedMessages } = buildChatPrompt({
    transcript,
    analysisSummary: analysis_summary,
    techniqueEvaluationsSummary: technique_evaluations_summary,
    reflectionSummary: reflection_summary,
    messages,
    techniqueNames: technique_names,
  });

  const model = env.GEMINI_TEXT_MODEL;

  // Build Gemini request contents
  // System instruction goes in systemInstruction, conversation in contents
  const contents = formattedMessages.map(m => ({
    role: m.role,
    parts: [{ text: m.content }],
  }));

  try {
    const response = await fetch(
      `${GEMINI_API_BASE}/v1beta/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{ text: systemPrompt }],
          },
          contents,
          generationConfig: {
            temperature: 0.7,
            maxOutputTokens: 2048,
          },
        }),
      }
    );

    if (!response.ok) {
      console.error('Gemini API error:', response.status);
      return c.json({
        error: 'Chat service error',
        status: response.status,
      }, 502);
    }

    const geminiResponse = await response.json() as GeminiGenerateResponse;

    if (!geminiResponse.candidates || geminiResponse.candidates.length === 0) {
      console.error('Gemini returned no candidates:', JSON.stringify(geminiResponse, null, 2));
      const blockReason = (geminiResponse as any).promptFeedback?.blockReason;
      return c.json({
        error: 'Chat response blocked or failed',
        message: blockReason ? 'Content was blocked by safety filters' : 'Chat service returned no results'
      }, 502);
    }

    const responseText = geminiResponse.candidates[0]?.content?.parts[0]?.text;

    if (!responseText) {
      console.error('Gemini candidate has no text content');
      return c.json({ error: 'Empty response from chat service' }, 502);
    }

    return c.json({
      message: responseText,
      usage: {
        input_tokens: geminiResponse.usageMetadata?.promptTokenCount,
        output_tokens: geminiResponse.usageMetadata?.candidatesTokenCount,
      },
    });

  } catch (err) {
    console.error('Chat request failed:', err);
    return c.json({
      error: 'Chat request failed'
    }, 500);
  }
});

/**
 * GET /chat/rate-limit
 * Returns current chat rate limit status for the user
 */
chatRoutes.get('/rate-limit', async (c) => {
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  const userId = authResult.userId!;
  const chatLimit = env.CHAT_RATE_LIMIT_PER_HOUR;
  const rateLimitKey = `rate:chat:${userId}`;
  const status = getRateLimitStatus(rateLimitKey, chatLimit);

  return c.json(status);
});
