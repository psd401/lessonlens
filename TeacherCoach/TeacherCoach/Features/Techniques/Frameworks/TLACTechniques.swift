import Foundation

/// TLAC (Teach Like A Champion 3.0) technique definitions
/// Curated for transcript-detectable techniques — techniques whose mechanics
/// live in verbal patterns, conversational turns, and word choice.
/// Based on Doug Lemov's 63 techniques, filtered to the 10 most reliably
/// identifiable from teacher-student dialogue.
struct TLACTechniques {
    static func createTechniques() -> [Technique] {
        [
            // Dialogue Structure — identifiable by sequence and pattern of conversational turns

            Technique(
                id: "no-opt-out",
                name: "No Opt Out",
                category: .engagement,
                description: "Ensuring that a sequence beginning with a student unable to answer ends with that same student saying the correct answer. The teacher routes the question to a peer or provides a cue, then returns to the original student — the 'conversational boomerang.'",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 1,
                lookFors: [
                    "Student says 'I don't know' or gives no answer",
                    "Teacher redirects to another student or provides a cue",
                    "Teacher returns to the original student for the answer",
                    "Original student successfully states the correct answer"
                ],
                exemplarPhrases: [
                    "Who can help Marcus out?",
                    "OK Marcus, now you tell me — what's the answer?",
                    "Let's come back to you. What did Jasmine say?",
                    "I'm going to come back to you in a moment"
                ]
            ),
            Technique(
                id: "cold-call",
                name: "Cold Call",
                category: .engagement,
                description: "Calling on students regardless of whether they've raised their hands, framed as voice equity — telling every student their thinking matters. The signature is question-first, name-second, with a deliberate pause between.",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 2,
                lookFors: [
                    "Question posed before student is named",
                    "Deliberate pause between question and name",
                    "Absence of 'Who can tell me...?' or 'Raise your hand if...'",
                    "Multiple different students called across consecutive questions"
                ],
                exemplarPhrases: [
                    "What is the setting of this story? ... Marcus?",
                    "How would you solve step two? ... Jasmine?",
                    "I'm going to Cold Call on this one",
                    "What's the evidence for that claim? ... Table three, Carlton?"
                ]
            ),
            Technique(
                id: "stretch-it",
                name: "Stretch It",
                category: .questioning,
                description: "When a student answers correctly, the teacher doesn't simply praise and move on — they immediately ask a deeper follow-up. The reward for being right is a harder question. Look for escalating cognitive demand across a question sequence.",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 3,
                lookFors: [
                    "Correct answer followed by immediate extension question",
                    "Absence of terminal praise ('Great, let's move on')",
                    "Successive deepening questions to the same student",
                    "Escalating cognitive demand across the sequence"
                ],
                exemplarPhrases: [
                    "Good — now tell me why",
                    "Correct — can you say more?",
                    "That's right. Is there a different approach?",
                    "Where in the text do you see evidence for that?",
                    "What if I changed this variable — would your answer change?"
                ]
            ),
            Technique(
                id: "call-and-response",
                name: "Call and Response",
                category: .engagement,
                description: "Asking the whole class to answer in unison, triggered by specific verbal cues. Includes countdown cues, fill-in-the-blank prompts, and the reinforcement variant where one student's answer is repeated by the whole class.",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 4,
                lookFors: [
                    "Group-addressing language before a choral response",
                    "Countdown cues or fill-in-the-blank prompts",
                    "Choral student responses in unison",
                    "Reinforcement pattern: one student answers, class repeats"
                ],
                exemplarPhrases: [
                    "Class, what is this called?",
                    "On three — one, two, three —",
                    "A solid always keeps its... [Students: Shape!]",
                    "Everyone, what did Marcus just say?"
                ]
            ),

            // Teacher Word Choice — identifiable by specific language at decision points

            Technique(
                id: "format-matters",
                name: "Format Matters",
                category: .feedback,
                description: "Holding students accountable not just for what they say but how they say it — complete sentences, correct grammar, technical vocabulary, audible volume. Uses ultra-short correction prompts and micro-correction sequences.",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 5,
                lookFors: [
                    "Brief correction prompts: 'Complete sentence,' 'Voice,' 'Use the technical term'",
                    "Three-turn micro-sequence: fragment → correction cue → improved restatement",
                    "Rollback technique: repeating the error back as a question",
                    "Sentence starters or partial prompts provided"
                ],
                exemplarPhrases: [
                    "Complete sentence.",
                    "Voice.",
                    "Use the technical term.",
                    "We was walking?",
                    "Tell me in a complete sentence...",
                    "The setting is..."
                ]
            ),
            Technique(
                id: "positive-framing",
                name: "Positive Framing",
                category: .management,
                description: "Delivering corrections, redirections, and information in language that communicates belief in students. Six verbal habits: Assume the Best, Live in the Now, Narrate the Positive, Plausible Anonymity, Challenge, and Talk Expectations.",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 6,
                lookFors: [
                    "Softening attributions: 'forgot,' 'seem to have,' 'I must not have been clear'",
                    "Forward-looking directives instead of backward-looking reprimands",
                    "Narrating compliant behavior by name: 'I see row two ready'",
                    "Corrections without naming names (plausible anonymity)",
                    "Absence of accusatory language, past-tense dwelling, or punitive threats"
                ],
                exemplarPhrases: [
                    "Show me your pencil moving",
                    "I see row two ready. Table five is there. Just waiting on a few more",
                    "Check yourself to make sure you've followed the directions",
                    "Let's see if we can beat our record",
                    "Write like the college students you're becoming"
                ]
            ),
            Technique(
                id: "right-is-right",
                name: "Right is Right",
                category: .questioning,
                description: "Not accepting partially correct answers as fully correct — refusing to 'round up' student responses. The teacher acknowledges partial correctness but withholds validation until the answer is genuinely complete and accurate.",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 7,
                lookFors: [
                    "Refusal to say 'correct' until the answer genuinely is",
                    "Redirecting off-topic answers back to the original question",
                    "Pushing for domain-specific technical vocabulary",
                    "Absence of premature 'Right!' or 'Good!' on incomplete answers"
                ],
                exemplarPhrases: [
                    "You're on the right track, but I want the complete answer",
                    "Almost — what's missing?",
                    "That's true, but it doesn't answer my question",
                    "That's interesting, but my question was...",
                    "What's the mathematical word for that?"
                ]
            ),
            Technique(
                id: "without-apology",
                name: "Without Apology",
                category: .instruction,
                description: "Never apologizing for worthy content. Avoiding hedging, apologetic, or blame-shifting language, and instead framing content as valuable, challenging, and exciting. Identifiable by both presence of positive framing and absence of undermining language.",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 8,
                lookFors: [
                    "Absence of 'I know this is boring/dry' hedging language",
                    "Absence of blame-shifting to external mandates",
                    "Content framed as valuable, challenging, or exciting",
                    "No lowering of expectations for certain students"
                ],
                exemplarPhrases: [
                    "This is one of the most powerful ideas you'll encounter this year",
                    "Scientists have spent decades wrestling with this very question",
                    "This is challenging work — and that's exactly why it matters",
                    "You're ready for this level of complexity"
                ]
            ),
            Technique(
                id: "precise-praise",
                name: "Precise Praise",
                category: .feedback,
                description: "Praise that is specific, action-focused, and differentiated from routine acknowledgment. Reinforces actions rather than traits, and conserves superlatives for genuinely exceptional moments. The ratio of precise-to-generic praise is a clean transcript metric.",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 9,
                lookFors: [
                    "Praise names the specific behavior or action",
                    "Reinforces actions rather than traits ('You found evidence' vs. 'You're smart')",
                    "Differentiated from routine acknowledgment ('Thank you' for compliance)",
                    "Superlatives reserved for genuinely exceptional moments"
                ],
                exemplarPhrases: [
                    "I noticed you went back to the text three times to support your argument — that's strong analytical reading",
                    "You found three pieces of evidence before drawing a conclusion",
                    "The way you revised your thesis after peer feedback shows real growth",
                    "You used the domain-specific vocabulary we practiced — that precision matters"
                ]
            ),

            // Student Language — identifiable through student speech patterns

            Technique(
                id: "habits-of-discussion",
                name: "Habits of Discussion",
                category: .engagement,
                description: "Normalizing conversational moves that make peer discussion coherent and connected. Uniquely identifiable through student speech patterns — peer references, building language, and structured sentence starters — measuring technique impact rather than just teacher intent.",
                frameworkId: TeachingFramework.tlac.rawValue,
                sortOrder: 10,
                lookFors: [
                    "Students referencing peers by name in their responses",
                    "Building language: 'I'd like to build on what Marcus said...'",
                    "Agreement/disagreement with reasoning: 'I agree because...'",
                    "Teacher scaffolding: 'Who can respond to what Sara just said?'"
                ],
                exemplarPhrases: [
                    "I'd like to build on what Marcus said...",
                    "I agree with Jasmine because...",
                    "Something that argument doesn't account for is...",
                    "Who can respond to what Sara just said?",
                    "Add on, Carlton"
                ]
            )
        ]
    }

    /// Returns the default enabled technique IDs for TLAC
    static var defaultEnabledIds: [String] {
        createTechniques().map { $0.id }
    }
}
