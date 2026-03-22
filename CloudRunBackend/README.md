# LessonLens API (Cloud Run)

Backend API for LessonLens macOS app. Handles authentication, text analysis, and video analysis via Gemini.

## Stack

- **Runtime**: Bun
- **Framework**: Hono.js
- **Deployment**: Google Cloud Run
- **AI**: Gemini 3.1 Pro (text) + Gemini 3 Flash (video)

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Health check |
| POST | `/auth/validate` | Validate Google ID token, return JWT |
| POST | `/auth/refresh` | Refresh expired session |
| POST | `/analyze` | Analyze transcript (Gemini) |
| GET | `/analyze/rate-limit` | Get text analysis rate limit status |
| POST | `/analyze/video` | Analyze video (Gemini) |
| GET | `/analyze/video/rate-limit` | Get video analysis rate limit status |
| POST | `/upload/initiate` | Initiate Gemini file upload |
| POST | `/chat` | Coaching chat message with session context |
| GET | `/chat/rate-limit` | Get chat rate limit status |

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GEMINI_API_KEY` | Yes | - | Google AI API key |
| `GOOGLE_CLIENT_ID` | Yes | - | Google OAuth client ID |
| `JWT_SECRET` | Yes | - | Secret for signing tokens |
| `ALLOWED_DOMAIN` | No | `psd401.net` | Email domain restriction |
| `GEMINI_TEXT_MODEL` | No | `gemini-3.1-pro-preview` | Text analysis model |
| `GEMINI_VIDEO_MODEL` | No | `gemini-3-flash-preview` | Video analysis model |
| `RATE_LIMIT_PER_HOUR` | No | `20` | Text analysis rate limit |
| `VIDEO_RATE_LIMIT_PER_HOUR` | No | `5` | Video analysis rate limit |
| `CHAT_RATE_LIMIT_PER_HOUR` | No | `50` | Chat message rate limit |
| `PORT` | No | `8080` | Server port |

## Local Development

```bash
# Install dependencies
bun install

# Set environment variables
export GEMINI_API_KEY=your-key
export GOOGLE_CLIENT_ID=your-client-id
export JWT_SECRET=your-secret

# Run development server
bun run dev
```

## Deployment

### Deploy to Cloud Run

```bash
# Authenticate with Google Cloud
gcloud auth login

# Set project
gcloud config set project YOUR_PROJECT_ID

# Deploy
gcloud run deploy lessonlens-api \
  --source . \
  --region us-west1 \
  --allow-unauthenticated \
  --set-env-vars="ALLOWED_DOMAIN=psd401.net"

# Set secrets (recommended for API keys)
gcloud run services update lessonlens-api \
  --set-secrets="GEMINI_API_KEY=gemini-api-key:latest,JWT_SECRET=jwt-secret:latest,GOOGLE_CLIENT_ID=google-client-id:latest"
```

## Rate Limiting

Uses in-memory rate limiting (resets on container restart):
- **Text analysis**: 20 requests/hour per user
- **Video analysis**: 5 requests/hour per user
- **Chat**: 50 messages/hour per user

Rate limit headers are included in responses:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`

## Project Structure

```
src/
├── index.ts              # App entry, CORS, rate limiting
└── routes/
    ├── auth.ts           # JWT validation, Google token verification
    ├── analyze.ts        # Text analysis with Gemini
    ├── analyze-video.ts  # Video analysis with Gemini
    ├── chat.ts           # Interactive coaching chat with Gemini
    └── upload.ts         # Gemini file upload initiation
```

## Analysis Flow

### Text Analysis
1. Client sends transcript + technique definitions
2. Backend validates JWT
3. Checks rate limit
4. Calls Gemini API with analysis prompt
5. Returns structured feedback

### Video Analysis
1. Client calls `/upload/initiate` to get Gemini upload URL
2. Client uploads video directly to Gemini
3. Client calls `/analyze/video` with file URI
4. Backend polls Gemini until file is processed (up to 10 min)
5. Backend calls Gemini with analysis prompt
6. Returns structured feedback
