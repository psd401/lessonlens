import { Hono } from 'hono';
import { verifySession } from './auth';
import { env } from '../index';

export const uploadRoutes = new Hono();

const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com';

interface InitiateUploadRequest {
  fileName: string;
  contentType: string;
  fileSize: number;
}

interface InitiateUploadResponse {
  uploadUrl: string;
  fileDisplayName: string;
}

const MAX_FILE_SIZE = 2 * 1024 * 1024 * 1024; // 2GB (Gemini File API limit)

// Gemini file names follow pattern: files/<alphanumeric-id>
const GEMINI_FILE_NAME_PATTERN = /^files\/[a-zA-Z0-9_-]+$/;

const ALLOWED_CONTENT_TYPES = [
  'video/mp4',
  'video/quicktime',
  'video/x-m4v',
  'video/webm',
];

/**
 * POST /upload/initiate
 * Initiates a resumable upload directly to Gemini File API
 * Returns the Gemini upload URL for direct client upload
 */
uploadRoutes.post('/initiate', async (c) => {
  // Verify authentication
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  // Parse request
  let body: InitiateUploadRequest;
  try {
    body = await c.req.json<InitiateUploadRequest>();
  } catch (err) {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { fileName, contentType, fileSize } = body;

  // Validate request
  if (!fileName || !contentType || !fileSize) {
    return c.json({ error: 'Missing fileName, contentType, or fileSize' }, 400);
  }

  if (!ALLOWED_CONTENT_TYPES.includes(contentType)) {
    return c.json({
      error: 'Invalid content type',
      message: `Allowed types: ${ALLOWED_CONTENT_TYPES.join(', ')}`,
    }, 400);
  }

  if (fileSize > MAX_FILE_SIZE) {
    return c.json({
      error: 'File too large',
      message: 'Maximum file size is 2GB',
      maxSize: MAX_FILE_SIZE,
    }, 400);
  }

  try {
    // Generate a unique display name
    const timestamp = Date.now();
    const sanitizedFileName = fileName.replace(/[^a-zA-Z0-9.-]/g, '_');
    const fileDisplayName = `${timestamp}-${sanitizedFileName}`;

    // Initiate resumable upload with Gemini
    const startResponse = await fetch(
      `${GEMINI_API_BASE}/upload/v1beta/files?key=${env.GEMINI_API_KEY}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'start',
          'X-Goog-Upload-Header-Content-Length': String(fileSize),
          'X-Goog-Upload-Header-Content-Type': contentType,
        },
        body: JSON.stringify({
          file: { displayName: fileDisplayName },
        }),
      }
    );

    if (!startResponse.ok) {
      console.error('Gemini upload initiation failed:', startResponse.status);
      return c.json({
        error: 'Failed to initiate upload'
      }, 502);
    }

    const uploadUrl = startResponse.headers.get('X-Goog-Upload-URL');
    if (!uploadUrl) {
      return c.json({ error: 'No upload URL returned from Gemini' }, 502);
    }

    return c.json<InitiateUploadResponse>({
      uploadUrl,
      fileDisplayName,
    });

  } catch (err) {
    console.error('Failed to initiate Gemini upload:', err);
    return c.json({
      error: 'Failed to initiate upload'
    }, 500);
  }
});

/**
 * POST /upload/status
 * Checks the status of an uploaded file in Gemini
 */
uploadRoutes.post('/status', async (c) => {
  // Verify authentication
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  const { fileName } = await c.req.json<{ fileName: string }>();

  if (!fileName) {
    return c.json({ error: 'Missing fileName' }, 400);
  }

  // Validate fileName format to prevent path traversal
  if (!GEMINI_FILE_NAME_PATTERN.test(fileName)) {
    return c.json({ error: 'Invalid fileName format' }, 400);
  }

  try {
    const response = await fetch(
      `${GEMINI_API_BASE}/v1beta/${fileName}?key=${env.GEMINI_API_KEY}`
    );

    if (!response.ok) {
      console.error('Failed to get file status:', response.status);
      return c.json({
        error: 'Failed to get file status'
      }, response.status);
    }

    const fileStatus = await response.json();
    return c.json(fileStatus);

  } catch (err) {
    console.error('Failed to get file status:', err);
    return c.json({
      error: 'Failed to get file status'
    }, 500);
  }
});

/**
 * DELETE /upload/:fileName
 * Deletes a file from Gemini
 */
uploadRoutes.delete('/:fileName{.+}', async (c) => {
  // Verify authentication
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  const fileName = c.req.param('fileName');

  if (!fileName) {
    return c.json({ error: 'Missing fileName' }, 400);
  }

  // Validate fileName format to prevent path traversal
  if (!GEMINI_FILE_NAME_PATTERN.test(fileName)) {
    return c.json({ error: 'Invalid fileName format' }, 400);
  }

  try {
    const response = await fetch(
      `${GEMINI_API_BASE}/v1beta/${fileName}?key=${env.GEMINI_API_KEY}`,
      { method: 'DELETE' }
    );

    if (!response.ok && response.status !== 404) {
      console.error('Failed to delete file:', response.status);
      return c.json({
        error: 'Failed to delete file'
      }, response.status);
    }

    return c.json({ success: true });

  } catch (err) {
    console.error('Failed to delete file:', err);
    return c.json({
      error: 'Failed to delete file'
    }, 500);
  }
});
