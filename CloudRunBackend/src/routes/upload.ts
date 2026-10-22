import { Hono } from 'hono';
import { verifySession } from './auth';
import { videoStorage } from '../index';

export const uploadRoutes = new Hono();

interface InitiateUploadRequest {
  contentType: string;
  fileSize: number;
}

const MAX_FILE_SIZE = 2 * 1024 * 1024 * 1024; // 2GB

const ALLOWED_CONTENT_TYPES = [
  'video/mp4',
  'video/quicktime',
  'video/x-m4v',
  'video/webm',
];

/**
 * POST /upload/initiate/gcs
 * Starts a Cloud Storage resumable upload into the temporary video bucket.
 * Returns the session URL, which the app uploads to with a plain PUT, and
 * the object name to pass to /analyze/video as gcsObject.
 */
uploadRoutes.post('/initiate/gcs', async (c) => {
  const authHeader = c.req.header('Authorization');
  const authResult = await verifySession(authHeader);

  if (!authResult.valid) {
    return c.json({ error: authResult.error }, 401);
  }

  if (!videoStorage) {
    return c.json({ error: 'Video upload is not configured' }, 503);
  }

  let body: InitiateUploadRequest;
  try {
    body = await c.req.json<InitiateUploadRequest>();
  } catch (err) {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { contentType, fileSize } = body;

  if (!contentType || !fileSize) {
    return c.json({ error: 'Missing contentType or fileSize' }, 400);
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
    // The app's file name is not used: object names carry no user details
    const objectName = videoStorage.newObjectName(authResult.userId!, contentType);
    const uploadUrl = await videoStorage.startResumableUpload(objectName, contentType, fileSize);
    return c.json({ uploadUrl, objectName });
  } catch (err) {
    console.error('Failed to initiate Cloud Storage upload:', err);
    return c.json({ error: 'Failed to initiate upload' }, 502);
  }
});
