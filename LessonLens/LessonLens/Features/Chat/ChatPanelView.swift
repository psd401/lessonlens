import SwiftUI
import SwiftData

/// Chat view for interactive coaching conversations about a specific session
struct ChatPanelView: View {
    @Bindable var recording: Recording
    @Bindable var chatSession: ChatSession

    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @State private var messageText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isPreparingTranscript = false

    /// Computed from analysis data
    private var suggestedStarters: [String] {
        guard let analysis = recording.analysis,
              let evaluations = analysis.techniqueEvaluations,
              !evaluations.isEmpty else { return [] }

        var starters: [String] = []

        // Lowest-rated technique
        if let lowestRated = evaluations
            .filter({ $0.wasObserved && $0.rating != nil })
            .min(by: { ($0.rating ?? 0) < ($1.rating ?? 0) }) {
            starters.append("What could I do differently with \(lowestRated.techniqueName)?")
        }

        // Growth areas
        if !analysis.growthAreas.isEmpty {
            starters.append("How can I improve on \"\(analysis.growthAreas[0])\"?")
        }

        // Highest-rated technique (strength)
        if let highestRated = evaluations
            .filter({ $0.wasObserved && $0.rating != nil })
            .max(by: { ($0.rating ?? 0) < ($1.rating ?? 0) }),
           starters.count < 3 {
            starters.append("Tell me more about how I used \(highestRated.techniqueName)")
        }

        return Array(starters.prefix(3))
    }

    private var sortedMessages: [ChatMessage] {
        chatSession.sortedMessages
    }

    /// Whether this recording needs transcript extraction before chat
    private var needsTranscriptExtraction: Bool {
        recording.isVideo && recording.transcript == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if needsTranscriptExtraction {
                transcriptExtractionView
            } else {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Suggested starters (only when no messages yet)
                            if sortedMessages.isEmpty {
                                suggestedStartersView
                            }

                            ForEach(sortedMessages) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                            }

                            if isSending {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: sortedMessages.count) { _, _ in
                        if let lastMessage = sortedMessages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isSending) { _, newValue in
                        if newValue {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }

                // Error display
                if let errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Dismiss") {
                            self.errorMessage = nil
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.red.opacity(0.1))
                }

                Divider()

                // Input
                chatInput
            }
        }
        .navigationTitle(chatSession.title)
    }

    // MARK: - Suggested Starters

    private var suggestedStartersView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask a follow-up question about your lesson:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(suggestedStarters, id: \.self) { starter in
                Button {
                    messageText = starter
                    sendMessage()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(PSDTheme.accent)

                        Text(starter)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(PSDTheme.accent)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Transcript Extraction

    private var transcriptExtractionView: some View {
        VStack(spacing: 16) {
            Spacer()

            if isPreparingTranscript {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing chat context...")
                        .font(.headline)
                    Text("Extracting audio and transcribing your video recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle")
                        .font(.largeTitle)
                        .foregroundStyle(PSDTheme.accent)

                    Text("Transcript Required")
                        .font(.headline)

                    Text("Chat requires a transcript for context. We'll extract audio from your video and transcribe it first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)

                    Button("Extract & Transcribe") {
                        startTranscriptExtraction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Chat Input

    private var chatInput: some View {
        HStack(spacing: 8) {
            TextField("Ask a question...", text: $messageText)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? .secondary : PSDTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding()
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let analysis = recording.analysis else { return }

        let userMessage = text
        messageText = ""
        errorMessage = nil

        // Auto-set title from first user message
        if chatSession.title == "New Chat" {
            let truncated = String(userMessage.prefix(40))
            chatSession.title = truncated.count < userMessage.count ? truncated + "..." : truncated
        }

        // Add user message
        let userChatMessage = ChatMessage(role: "user", content: userMessage)
        modelContext.insert(userChatMessage)
        userChatMessage.session = chatSession
        try? modelContext.save()

        isSending = true

        Task {
            do {
                let session = try await services.authService.getValidSession(updating: appState)

                // Build transcript context
                let transcriptText: String
                if let transcript = recording.transcript {
                    transcriptText = ChatService.formatTimestampedTranscript(transcript: transcript)
                } else {
                    transcriptText = "No transcript available."
                }

                // Build message history for API
                let allMessages = chatSession.sortedMessages.map {
                    ChatMessagePayload(role: $0.role, content: $0.content)
                }

                // Build reflection summary
                var reflectionSummary: String?
                if let reflection = recording.reflection {
                    reflectionSummary = ChatService.buildReflectionSummary(reflection: reflection)
                }

                // Build technique names and evaluations summary
                let techniqueNames = (analysis.techniqueEvaluations ?? []).map { $0.techniqueName }
                let evaluationsSummary = ChatService.buildTechniqueEvaluationsSummary(analysis: analysis)

                let responseText = try await services.chatService.sendMessage(
                    transcript: transcriptText,
                    analysisSummary: analysis.overallSummary,
                    techniqueEvaluationsSummary: evaluationsSummary,
                    reflectionSummary: reflectionSummary,
                    messages: allMessages,
                    techniqueNames: techniqueNames,
                    sessionToken: session.accessToken
                )

                // Add assistant message
                let assistantMessage = ChatMessage(role: "assistant", content: responseText)
                modelContext.insert(assistantMessage)
                assistantMessage.session = chatSession
                try? modelContext.save()

            } catch AuthError.cancelled {
                // User dismissed sign-in popup, no error to show
            } catch {
                errorMessage = error.localizedDescription
            }

            isSending = false
        }
    }

    private func startTranscriptExtraction() {
        guard let videoURL = recording.absoluteVideoPath else { return }

        isPreparingTranscript = true

        Task {
            do {
                // Extract audio from video
                let audioURL = try await services.audioExtractionService.extractAudio(from: videoURL)
                recording.audioFilePath = audioURL.lastPathComponent

                // Transcribe
                let transcript = try await services.transcriptionService.transcribe(recording: recording)
                recording.transcript = transcript
                try modelContext.save()

            } catch {
                errorMessage = "Failed to prepare transcript: \(error.localizedDescription)"
            }

            isPreparingTranscript = false
        }
    }
}
