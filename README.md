# LessonLens

Native macOS app for Peninsula SD teachers to record teaching sessions, receive local transcription via WhisperKit, and get AI-powered feedback on specific teaching techniques. Teachers complete a guided self-reflection before viewing AI analysis, then can dig deeper through interactive coaching chat.

## Features

- **Live Recording** - Record teaching sessions directly in the app
- **Audio Import** - Import voice memos and audio files (M4A, MP3, WAV, CAF)
- **Video Import** - Import classroom recordings (MP4, MOV, M4V, WebM)
- **Local Transcription** - On-device transcription using WhisperKit (Apple Silicon)
- **Wait Time Detection** - Automatic detection of pauses (3+ seconds) for wait time analysis
- **AI Analysis** - Gemini-powered feedback on teaching techniques
- **Video Analysis** - Gemini-powered visual+audio analysis for classroom dynamics
- **Guided Self-Reflection** - Multi-step reflection wizard before viewing AI feedback (what went well, what to change, self-rate techniques, pick focus areas)
- **Self vs AI Comparison** - Side-by-side view of teacher's self-ratings against AI ratings with delta indicators
- **Interactive Coaching Chat** - Follow-up questions with AI using full transcript + analysis context, with timestamped evidence citations
- **Multiple Frameworks** - Seven research-based teaching evaluation frameworks
- **Star Ratings** - Optional 1-5 star ratings with visual legend
- **PDF & Markdown Export** - Export analysis reports with customizable content, including self-reflection data
- **Domain-Restricted Auth** - Google OAuth (ASWebAuthenticationSession) limited to @psd401.net accounts

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    macOS App (SwiftUI)                      │
├─────────────────────────────────────────────────────────────┤
│  Recording → Transcription (WhisperKit) → Analysis Request  │
│  Video Import → Direct Upload to Gemini → Video Analysis    │
│  Self-Reflection → Comparison View → Coaching Chat          │
│                           ↓                                 │
│              Local Storage (SwiftData + Media Files)        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ↓ HTTPS
┌─────────────────────────────────────────────────────────────┐
│              Cloud Run Backend (Hono.js)                    │
├─────────────────────────────────────────────────────────────┤
│  /auth/validate    │ Google JWT → Domain check              │
│  /analyze          │ → Gemini API (text analysis)           │
│  /analyze/video    │ → Gemini API (video analysis)          │
│  /chat             │ → Gemini API (coaching conversation)   │
│  /upload/initiate  │ → Gemini File Upload                   │
│  Rate Limiting     │ 20 text/hr, 5 video/hr, 50 chat/hr    │
└─────────────────────────────────────────────────────────────┘
```

## Requirements

### macOS App
- macOS 14.0+ (Sonoma)
- Xcode 15.2+
- Apple Silicon Mac (for WhisperKit)

### Backend
- Google Cloud Run account
- Google AI API key (Gemini)

## Project Structure

```
lessonlens/
├── LessonLens/                   # macOS App
│   ├── LessonLens/
│   │   ├── App/                  # Entry point, AppState, ServiceContainer
│   │   ├── Features/
│   │   │   ├── Authentication/   # Google OAuth (ASWebAuthenticationSession)
│   │   │   ├── Recording/        # Audio/video recording & import
│   │   │   ├── Transcription/    # WhisperKit integration
│   │   │   ├── Analysis/         # Gemini API integration
│   │   │   ├── Reflection/       # Guided self-reflection wizard & comparison
│   │   │   ├── Chat/             # Interactive coaching chat
│   │   │   ├── Techniques/       # Teaching frameworks & technique library
│   │   │   ├── Export/           # PDF & Markdown export
│   │   │   ├── Growth/           # Growth tracking dashboard
│   │   │   ├── HowItWorks/       # How It Works explainer page
│   │   │   ├── Legal/            # Terms & Privacy views
│   │   │   └── Settings/         # User preferences
│   │   └── Core/
│   │       ├── Models/           # SwiftData models (Recording, Analysis, Reflection, ChatSession, etc.)
│   │       ├── Views/            # Shared UI components
│   │       ├── Theme/            # PSD branding (colors, typography, modifiers)
│   │       └── Services/         # Utility services
│   └── LessonLens.xcodeproj
├── CloudRunBackend/              # Primary backend (Google Cloud Run)
│   └── src/routes/               # API routes (auth, analyze, chat, upload)
├── shared/                       # Shared prompt templates (text, video, chat)
│   └── prompts/
├── scripts/                      # Deployment automation scripts
│   ├── setup.sh                  # Backend setup wizard (GCP + Cloud Run)
│   └── configure-app.sh          # App configuration script (bundle ID, URLs)
├── docs/                         # Documentation
│   ├── DEPLOYMENT.md             # District deployment guide
│   └── DEPLOYMENT_CHECKLIST.md   # Printable deployment checklist
└── CloudflareWorker/             # Alternative backend (Cloudflare Workers)
    └── src/routes/               # API routes
```

## User Flow

1. **Record or Import** — Teacher records a lesson or imports audio/video
2. **Transcribe** — Audio transcribed locally via WhisperKit (or video sent to Gemini)
3. **Analyze** — Transcript sent to Gemini for technique evaluation
4. **Self-Reflect** — Teacher completes guided reflection before viewing AI feedback:
   - What went well?
   - What would you change?
   - Self-rate each technique (1-5 stars)
   - Pick 1-2 focus techniques
   - (Can skip to go directly to feedback)
5. **Compare** — Side-by-side view of self-ratings vs AI ratings with delta indicators
6. **Review Feedback** — Full AI analysis with strengths, growth areas, technique evaluations, and next steps
7. **Chat** — Ask follow-up questions with AI referencing timestamped transcript evidence
8. **Export** — PDF or Markdown report with optional reflection data

## Teaching Frameworks

The app ships with seven research-based frameworks for evaluating teaching:

### TLAC (Teach Like a Champion)

| Category | Techniques |
|----------|------------|
| Questioning | Wait Time, Higher-Order Questions |
| Engagement | Cold Calling, Think-Pair-Share |
| Feedback | Specific Praise, Check for Understanding |
| Management | Positive Framing |
| Instruction | Modeling/Think Aloud, Scaffolded Practice |
| Differentiation | Strategic Grouping |

### Danielson Framework for Teaching

| Domain | Components |
|--------|------------|
| Domain 2: Classroom Environment | 2a: Respect & Rapport, 2b: Culture for Learning, 2c: Managing Procedures, 2d: Managing Behavior |
| Domain 3: Instruction | 3a: Communicating with Students, 3b: Questioning & Discussion, 3c: Engaging Students, 3d: Using Assessment, 3e: Flexibility & Responsiveness |

### Rosenshine's Principles of Instruction

| Principle | Focus |
|-----------|-------|
| Daily Review | Begin lessons with review of previous learning |
| Small Steps | Present new material in small, manageable steps |
| Ask Questions | Frequent questioning to check understanding |
| Provide Models | Demonstrate and model procedures |
| Guide Practice | Supervised practice with feedback |
| Check Understanding | Verify comprehension before moving on |
| High Success Rate | Ensure students achieve mastery |
| Provide Scaffolds | Support complex tasks with frameworks |
| Independent Practice | Allow autonomous practice time |
| Weekly/Monthly Review | Regular review cycles |

### AVID (Advancement Via Individual Determination)

Focuses on WICOR strategies: Writing, Inquiry, Collaboration, Organization, and Reading.

### National Board for Professional Teaching Standards

Based on the Five Core Propositions for accomplished teaching.

### PSD Essentials

Peninsula School District's locally defined essential teaching practices.

### Behavior Support Strategies

Proactive and responsive strategies teachers can implement immediately to support student behavior and classroom management. Includes routines & expectations, environmental arrangement, greeting & connection, specific behavioral praise, calm redirection, de-escalation language, choice & autonomy, group momentum, restorative check-ins, and next-day reset.

Each technique includes:
- Description
- Look-fors (observable indicators)
- Exemplar phrases

## Analysis Methods

### Audio Analysis (Gemini)
- Records or imports audio
- Transcribes locally via WhisperKit
- Analyzes transcript for teaching techniques (Gemini 3 Pro)
- Detects wait time pauses (3+ seconds)
- Cost: ~$0.01-0.03 per analysis
- Rate limit: 20 analyses/hour

### Video Analysis (Gemini)
- Imports video recordings (5-50 minutes, max 2GB)
- Uploads directly to Google Gemini
- Analyzes visual + audio content (Gemini 3 Flash)
- Observes teacher positioning, student engagement, non-verbal cues
- Cost: ~$0.15-0.27 per analysis
- Rate limit: 5 analyses/hour

### Interactive Coaching Chat (Gemini)
- Follow-up questions after analysis is complete
- Full context: timestamped transcript, analysis summary, technique evaluations, self-reflection
- Transcript formatted with `[MM:SS-MM:SS]` timestamps and pause markers for evidence citation
- Temperature 0.7 for more conversational responses
- Suggested starter questions generated from analysis data
- Video-only recordings auto-extract transcript before chat
- Rate limit: 50 messages/hour

## Rating Scale

When star ratings are enabled, each technique receives a 1-5 star rating:

| Rating | Level | Description |
|--------|-------|-------------|
| 1 | Developing | Technique not observed or needs significant development |
| 2 | Emerging | Beginning to implement technique with inconsistent results |
| 3 | Proficient | Solid implementation with room for refinement |
| 4 | Accomplished | Effective and consistent use of technique |
| 5 | Exemplary | Strong, consistent implementation that could serve as a model |

## Data Models

### Core Models (SwiftData)
- **Recording** — Teaching session with audio/video file paths, status, and relationships to Transcript, Analysis, Reflection, and ChatSession
- **Transcript** — Full text with timestamped segments and detected pauses
- **Analysis** — AI-generated summary, strengths, growth areas, next steps, and technique evaluations
- **TechniqueEvaluation** — Per-technique rating, feedback, evidence, and suggestions
- **Reflection** — Teacher's self-reflection: what went well, what to change, self-ratings, focus techniques
- **ChatSession** — Coaching conversation container with cascade-deleted messages
- **ChatMessage** — Individual message (role: user/assistant) with timestamp

## Setup

> **Deploying for another district?** See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the full deployment guide with automated setup scripts.

### Quick Start (PSD Development)

#### 1. Configure Google OAuth

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable Google Sign-In API
4. Create OAuth 2.0 credentials (iOS application type, bundle ID: `com.peninsula.lessonlens`)
5. Note the Client ID

#### 2. Deploy Backend (Cloud Run)

```bash
# Automated (recommended)
bash scripts/setup.sh

# Or manually:
cd CloudRunBackend
bun install
gcloud run deploy lessonlens-api --source .
```

#### 3. Build macOS App

```bash
cd LessonLens
open LessonLens.xcodeproj
# Build and run (⌘R) — Google Client ID is configured in ServiceContainer.swift
```

### Environment Variables

#### macOS App (Xcode Scheme)
```
DEV_BYPASS_AUTH=1        # Optional: bypass OAuth for local testing
DEV_USE_BUNDLED_MODEL=1  # Optional: use bundled WhisperKit model
```

#### Backend (Cloud Run)
- `GEMINI_API_KEY` - Google AI API key
- `GOOGLE_CLIENT_ID` - Google OAuth client ID
- `JWT_SECRET` - Secret for signing session tokens (min 32 chars)
- `ALLOWED_DOMAIN` - Email domain restriction (e.g., `psd401.net`)
- `GEMINI_TEXT_MODEL` - Text analysis model (default: `gemini-3-pro-preview`)
- `GEMINI_VIDEO_MODEL` - Video analysis model (default: `gemini-3-flash-preview`)
- `RATE_LIMIT_PER_HOUR` - Text analysis rate limit (default: 20)
- `VIDEO_RATE_LIMIT_PER_HOUR` - Video analysis rate limit (default: 5)
- `CHAT_RATE_LIMIT_PER_HOUR` - Chat message rate limit (default: 50)

## API Endpoints

### Authentication
| Endpoint | Description |
|----------|-------------|
| `POST /auth/validate` | Validate Google ID token, return session JWT |
| `POST /auth/refresh` | Refresh expired session token |

### Analysis
| Endpoint | Description |
|----------|-------------|
| `POST /analyze` | Analyze transcript for teaching techniques (Gemini) |
| `POST /analyze/video` | Analyze uploaded video (Gemini) |
| `GET /analyze/rate-limit` | Get current text analysis rate limit status |
| `GET /analyze/video/rate-limit` | Get current video analysis rate limit status |

### Chat
| Endpoint | Description |
|----------|-------------|
| `POST /chat` | Send coaching chat message with session context |
| `GET /chat/rate-limit` | Get current chat rate limit status |

### Video Upload
| Endpoint | Description |
|----------|-------------|
| `POST /upload/initiate` | Initiate Gemini video upload, get upload URL |

## Privacy & Security

- **Audio stays local** - Recordings stored only on user's device
- **Transcripts sent for analysis** - Audio transcribed locally, only text sent to Gemini
- **Videos uploaded to Gemini** - Deleted after analysis completion
- **Reflections stored locally** - Self-reflection data stays on device, optionally included in chat context
- **Chat messages stored locally** - Conversation history persisted in SwiftData
- **Domain-restricted** - Only @psd401.net accounts can sign in
- **Secure storage** - Session tokens stored in macOS Keychain (sandboxed)
- **Rate limiting** - Per-user hourly limits prevent abuse (separate limits for analysis, video, and chat)

## Development

### Local Development (No OAuth)

Set `DEV_BYPASS_AUTH=1` in your Xcode scheme environment variables to bypass Google authentication during development.

1. In Xcode, select Product → Scheme → Edit Scheme
2. Select Run → Arguments → Environment Variables
3. Add `DEV_BYPASS_AUTH` with value `1`

### Run Backend Locally
```bash
cd CloudRunBackend
bun run dev
```

### Run Tests
```bash
# Backend
cd CloudRunBackend
bun test

# macOS App (in Xcode)
⌘U
```

## Export Options

Analysis reports can be exported in two formats:

### PDF Export
- Multi-page layout with page numbers
- Configurable sections (summary, strengths, growth areas, techniques, next steps)
- Optional self-reflection section (what went well, what to change, self-ratings table, focus areas)
- Star rating visualization
- Evidence and suggestions for each technique

### Markdown Export
- Plain text format for easy sharing
- Same section configurability as PDF, including self-reflection
- Compatible with note-taking apps and documentation systems

## Deployment

For full multi-district deployment instructions, see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) and the [printable checklist](docs/DEPLOYMENT_CHECKLIST.md).

### MDM Distribution

1. Archive the app in Xcode (Product → Archive)
2. Export with Developer ID signing
3. Notarize the app
4. Package as `.pkg`: `pkgbuild --component LessonLens.app --install-location /Applications LessonLens.pkg`
5. Upload to your MDM (Jamf, Mosyle, Kandji, etc.) for distribution

## License

This project is licensed under the [MIT License](LICENSE).

Copyright (c) 2026 Peninsula School District.

See [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) for attribution of open-source dependencies.
