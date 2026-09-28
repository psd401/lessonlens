// LessonLens help content — edit this file to change the help page.
// Each section renders as a step with a screenshot and an optional "Show me" tour.
// Tour hotspots are percentages of the screenshot: { x, y, w, h } from the top-left.
// image: null renders a placeholder frame that still shows the hotspot areas.
// UI labels below are quoted from the app; keep them in sync when the app changes.
window.LESSONLENS_HELP = {
  "updated": "2026-09-25",
  "appVersion": "1.1.1",
  "sections": [
    {
      "id": "capture",
      "title": "Capture a lesson",
      "summary": "Record live, or bring in audio or video you already have (5 to 50 minutes). Then turn the audio into text on your Mac.",
      "steps": [
        "From <b>Home</b>, choose <b>New Recording</b>, <b>Import Audio</b>, or <b>Import Video</b>. The <b>+</b> button at the top right does the same from anywhere.",
        "<b>New Recording:</b> add an optional title, click the big record button, and click <b>Done</b> when you finish. <b>Import:</b> pick an audio file (such as a Voice Memo) or a video file.",
        "Open the session and click <b>Start Transcription</b>. Your audio is turned into text on your Mac and is not uploaded.",
        "Review the <b>Transcript</b>. Each line has a timestamp, and long pauses may be marked as wait time."
      ],
      "image": "img/home.png",
      "alt": "LessonLens home screen with New Recording, Import Audio, and Import Video tiles",
      "tour": [
        {
          "x": 33.2,
          "y": 58.6,
          "w": 19.6,
          "h": 20,
          "title": "New Recording",
          "text": "Record a lesson with your Mac's microphone."
        },
        {
          "x": 54.6,
          "y": 58.6,
          "w": 19.6,
          "h": 20,
          "title": "Import Audio",
          "text": "Use a Voice Memo or other audio file."
        },
        {
          "x": 75.9,
          "y": 59.2,
          "w": 19.6,
          "h": 19,
          "title": "Import Video",
          "text": "Use a classroom video recording."
        },
        {
          "x": 94.1,
          "y": 1.2,
          "w": 5,
          "h": 5.5,
          "title": "Add from anywhere",
          "text": "The + menu has the same three options on every screen."
        },
        {
          "x": 1.3,
          "y": 36.8,
          "w": 25.5,
          "h": 14.7,
          "title": "Your sessions",
          "text": "Every lesson appears here, newest first. Right-click one to rename it."
        }
      ],
      "note": "For video, choose <b>Video Analysis</b> (recommended) or <b>Audio Only</b>. Video Analysis sends the video to Google Gemini for feedback."
    },
    {
      "id": "analyze",
      "title": "Choose what you want feedback on",
      "summary": "Pick a framework and a few techniques. Focused choices give more useful feedback.",
      "steps": [
        "Click <b>Configure &amp; Analyze</b>.",
        "Choose a <b>Teaching Framework</b>, such as PSD Instructional Essentials, Danielson, or Teach Like a Champion.",
        "Check 3 to 5 <b>Techniques</b>. Click ⓘ next to any technique to see its look-fors.",
        "Leave <b>Include Star Ratings</b> on if you want 1 to 5 star ratings and growth tracking.",
        "Click <b>Start Analysis</b>."
      ],
      "image": "img/analyze.png",
      "alt": "The Configure Analysis sheet with the Danielson framework and four techniques selected",
      "tour": [
        {
          "x": 21.9,
          "y": 19.6,
          "w": 54.3,
          "h": 12.8,
          "title": "Teaching Framework",
          "text": "Seven frameworks to choose from."
        },
        {
          "x": 43,
          "y": 37.6,
          "w": 31.5,
          "h": 4.6,
          "title": "4 selected",
          "text": "3 to 5 techniques gives the most focused feedback. The tip turns orange if you pick too many."
        },
        {
          "x": 21.9,
          "y": 43,
          "w": 54.3,
          "h": 47.4,
          "title": "Techniques",
          "text": "Click ⓘ on any technique to see its look-fors."
        },
        {
          "x": 65.6,
          "y": 93.6,
          "w": 13,
          "h": 4.8,
          "title": "Start Analysis",
          "text": "Your choices are remembered for next time."
        }
      ],
      "note": "Want to know what a framework looks for first? Click <b>Frameworks</b> in the sidebar to browse every technique with look-fors and example phrases."
    },
    {
      "id": "reflect",
      "title": "Reflect first",
      "summary": "Before you see the AI's feedback, you can reflect on the lesson yourself. It's optional.",
      "steps": [
        "Answer <b>What went well?</b> and <b>What would you change?</b>",
        "Rate yourself on each technique.",
        "Choose 1 or 2 techniques to focus on.",
        "Click <b>Submit Reflection</b>, or <b>Skip to Feedback</b> at any step."
      ],
      "note": "Skipping is final for that session. Your reflection is shown next to the AI's view afterward.",
      "image": "img/reflect.png",
      "alt": "Step 1 of the self-reflection, with a sample answer",
      "tour": [
        {
          "x": 31.3,
          "y": 28.4,
          "w": 65.9,
          "h": 7,
          "title": "Step 1 of 5",
          "text": "Five short steps before you see the AI's feedback."
        },
        {
          "x": 33.1,
          "y": 44.5,
          "w": 62.4,
          "h": 21.5,
          "title": "Your reflection",
          "text": "Your own view of the lesson, in your words."
        },
        {
          "x": 32.2,
          "y": 72.7,
          "w": 11.1,
          "h": 4,
          "title": "Skip to Feedback",
          "text": "Available on every step."
        },
        {
          "x": 88.9,
          "y": 72.1,
          "w": 7.6,
          "h": 5.2,
          "title": "Next",
          "text": "The last step has Submit Reflection, which unlocks the Self vs AI Comparison."
        }
      ]
    },
    {
      "id": "feedback",
      "title": "Read your feedback",
      "summary": "Feedback is written for your growth. It is coaching, not evaluation.",
      "steps": [
        "Start with the <b>Summary</b>, then <b>Strengths</b> and <b>Potential Growth Areas</b>.",
        "Open any technique under <b>Technique Feedback</b> to see quotes from your lesson as <b>Evidence</b> and ideas under <b>Suggestions</b>.",
        "If you reflected, compare your view with the AI's in <b>Self vs AI Comparison</b>.",
        "Finish with <b>Next Steps to Consider</b>."
      ],
      "image": "img/feedback.png",
      "alt": "Feedback for a sample lesson: summary, strengths, and potential growth areas",
      "tour": [
        {
          "x": 31.4,
          "y": 26.8,
          "w": 63.9,
          "h": 8.1,
          "title": "Self vs AI Comparison",
          "text": "If you reflected, open this to compare your ratings with the AI's."
        },
        {
          "x": 31.4,
          "y": 39.6,
          "w": 63.9,
          "h": 23.6,
          "title": "Summary",
          "text": "A short overview of the lesson."
        },
        {
          "x": 31.4,
          "y": 67,
          "w": 31,
          "h": 32.5,
          "title": "Strengths",
          "text": "What worked, tied to techniques."
        },
        {
          "x": 64.2,
          "y": 67,
          "w": 31.1,
          "h": 26.8,
          "title": "Potential Growth Areas",
          "text": "Ideas to try next. Scroll down for Technique Feedback with evidence quotes and suggestions."
        }
      ]
    },
    {
      "id": "chat",
      "title": "Talk it through with a coach",
      "summary": "Ask follow-up questions about your lesson in a private coaching chat.",
      "steps": [
        "At the bottom of your feedback, click <b>Coaching Chats</b>.",
        "Click <b>New Chat</b>, then open it.",
        "Pick a suggested question or type your own in <b>Ask a question...</b>",
        "Start as many chats per lesson as you like."
      ],
      "image": "img/chat.png",
      "alt": "A new coaching chat with three suggested questions",
      "tour": [
        {
          "x": 24,
          "y": 21.8,
          "w": 52,
          "h": 28.2,
          "title": "Suggested questions",
          "text": "Starters based on your feedback. Click one to ask it."
        },
        {
          "x": 24,
          "y": 91.7,
          "w": 52.7,
          "h": 5.8,
          "title": "Ask a question...",
          "text": "Type anything about your lesson."
        },
        {
          "x": 23.3,
          "y": 9.5,
          "w": 3.4,
          "h": 4.7,
          "title": "Back",
          "text": "Returns to the list of chats for this lesson."
        }
      ]
    },
    {
      "id": "growth",
      "title": "See your growth",
      "summary": "Track star ratings across lessons for the same framework.",
      "steps": [
        "Click <b>Growth</b> in the sidebar.",
        "Pick a framework.",
        "Read <b>Overall Trend</b>, <b>Technique Breakdown</b>, and <b>Patterns &amp; Insights</b>."
      ],
      "note": "Needs at least two analyzed lessons with star ratings on, using the same framework.",
      "image": null,
      "alt": "The Growth Dashboard",
      "tour": [
        {
          "x": 4,
          "y": 14,
          "w": 92,
          "h": 26,
          "title": "Overall Trend",
          "text": "Your average rating over time."
        },
        {
          "x": 4,
          "y": 44,
          "w": 92,
          "h": 28,
          "title": "Technique Breakdown",
          "text": "Ratings for each technique."
        },
        {
          "x": 4,
          "y": 76,
          "w": 92,
          "h": 18,
          "title": "Patterns & Insights",
          "text": "Where you're strong and what's worth revisiting."
        }
      ]
    }
  ],
  "tips": [
    {
      "q": "How do I sign in?",
      "a": "Click <b>Sign in with Google</b> and choose your @psd401.net account. Other accounts can't sign in."
    },
    {
      "q": "How do I save or share my feedback?",
      "a": "In a finished session, click <b>Export</b> in the toolbar, choose <b>PDF</b> or <b>Markdown</b>, and pick the sections to include. The transcript is left out unless you add it. Sharing is always your choice."
    },
    {
      "q": "How long can a lesson be?",
      "a": "5 to 50 minutes, for recordings and imports."
    },
    {
      "q": "Who can see my lessons?",
      "a": "Only you. No administrator, evaluator, or colleague can see your sessions. LessonLens is voluntary and is never used for evaluation."
    },
    {
      "q": "Where do my recordings go?",
      "a": "Audio is turned into text on your Mac. Only the text is sent for AI feedback, and it is never permanently stored. If you choose Video Analysis, the video is sent to Google Gemini for feedback."
    },
    {
      "q": "How do I rename or delete a session?",
      "a": "Right-click a session in the sidebar and choose <b>Rename</b>. To delete, open the session and click the trash button in the toolbar."
    },
    {
      "q": "What does Re-analyze do?",
      "a": "It creates a new copy of the session, named with \"(Re-analysis)\" and today's date, and analyzes it with the framework and techniques you choose. The copy starts with a fresh reflection. <b>Your original feedback, reflection, and coaching chats stay as they are.</b>"
    }
  ]
};
