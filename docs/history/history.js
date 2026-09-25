// LessonLens project history — edit this file to add or change milestones.
// Each stop renders as a signpost along the road in index.html.
// Sources: git log and GitHub Releases. Keep claims tied to that record.
// Audience is non-developers: avoid dev jargon such as "commits".
window.LESSONLENS_HISTORY = {
  updated: "2026-09-25",
  currentVersions: "App v1.1.1 · Server v1.2.0",
  stats: [
    { value: "Jan 2026", label: "project start" },
    { value: "7", label: "teaching frameworks" },
    { value: "2", label: "app releases" }
  ],
  legs: [
    {
      name: "Prototype",
      stops: [
        {
          date: "2026-01-17",
          title: "Day one: Teacher Coach",
          body: "The first working Mac app: record a lesson, turn the audio into text on the teacher's own Mac, and send only that text out for AI feedback. Nothing is kept along the way.",
          tags: ["recording", "private transcription"]
        },
        {
          date: "2026-01-20",
          title: "Fits a teacher's real week",
          body: "Bring in recordings from a phone's Voice Memos, pick a teaching framework (Teach Like a Champion or Danielson), turn star ratings on or off, save feedback as a PDF, and see how much wait time you gave students.",
          tags: ["audio import", "export", "wait time"]
        }
      ]
    },
    {
      name: "Build-out",
      stops: [
        {
          date: "2026-01-27",
          title: "Video and a secure server",
          body: "Teachers can upload lesson video, not just audio. A more secure server replaces the prototype's, with added protections the same week.",
          tags: ["video", "security"]
        },
        {
          date: "2026-01-29",
          title: "Six frameworks",
          body: "Rosenshine's Principles, AVID WICOR, National Board Standards, and PSD Instructional Essentials join Teach Like a Champion and Danielson.",
          tags: ["frameworks"]
        },
        {
          date: "2026-02-24",
          title: "One AI provider",
          body: "All feedback now comes from one AI model, Google Gemini.",
          tags: ["Gemini"]
        }
      ]
    },
    {
      name: "From feedback to coaching",
      stops: [
        {
          date: "2026-03-10",
          title: "Reflection before feedback",
          body: "Teachers reflect on their own lesson first, then talk it through with an AI coach. A one-way report becomes a conversation, and a teacher can start more than one conversation per lesson.",
          tags: ["self-reflection", "coaching chat"]
        },
        {
          date: "2026-03-11",
          title: "Growth over time, renamed LessonLens",
          body: "A dashboard shows growth across lessons. Teachers can choose the tone of their feedback, a seventh framework focuses on behavior support, and a Framework Explorer explains each framework. Teacher Coach becomes LessonLens.",
          tags: ["growth dashboard", "new name"]
        },
        {
          date: "2026-03-12",
          title: "Free to share",
          body: "LessonLens becomes open source, so other districts can use and adapt it. A How It Works page inside the app, a setup guide for districts, and draft terms and privacy notice arrive the same day.",
          tags: ["open source", "district setup guide"]
        }
      ]
    },
    {
      name: "Release",
      stops: [
        {
          date: "2026-03-24",
          title: "First releases: v1.1.0 and v1.1.1",
          body: "The app is packaged and verified with Apple so district IT can install it on teacher Macs. Two releases, including fixes found in testing, are published the same day.",
          tags: ["v1.1.0", "v1.1.1"],
          milestone: true
        },
        {
          date: "2026-03-27",
          title: "Opened to the public",
          body: "Before the code went public, internal district details and a test-only shortcut past sign-in were removed. The project page now leads with how teacher data is protected.",
          tags: ["privacy"]
        }
      ]
    },
    {
      name: "Maintain",
      stops: [
        {
          date: "2026-09-15",
          title: "A newer AI model",
          body: "Feedback, coaching chat, and video analysis move to Google's newer Gemini 3.8 Flash model. The change happens on the server, so teachers get it without updating the app.",
          tags: ["Gemini 3.8 Flash"],
          current: true
        }
      ]
    }
  ]
};
