import SwiftUI
import SwiftData

struct RecordingDetailView: View {
    @Bindable var recording: Recording

    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @State private var showingDeleteConfirmation = false
    @State private var showingAnalysisConfig = false
    @State private var showingExportConfig = false
    @State private var showingVideoAnalysisConfig = false
    @State private var isProcessing = false
    @State private var processingMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                RecordingHeaderView(recording: recording)

                Divider()

                // Video preview for video recordings
                if recording.isVideo {
                    VideoPlayerView(videoURL: recording.absoluteVideoPath)
                        .frame(height: 300)
                        .padding(.bottom, 8)
                }

                // Actions based on status
                switch recording.status {
                case .recorded:
                    if recording.isVideo {
                        VideoAnalysisOptionsView(
                            isProcessing: isProcessing,
                            onVideoAnalysis: { showingVideoAnalysisConfig = true },
                            onAudioAnalysis: startAudioExtractionAndTranscription
                        )
                    } else {
                        ActionPromptView(
                            title: "Ready for Transcription",
                            description: "Transcribe this recording to prepare it for analysis.",
                            buttonTitle: "Start Transcription",
                            isLoading: isProcessing,
                            action: startTranscription
                        )
                    }

                case .uploading:
                    ProcessingView(
                        title: "Uploading Video...",
                        progress: services.videoAnalysisService.uploadProgress
                    )

                case .transcribing:
                    ProcessingView(
                        title: "Transcribing...",
                        progress: services.transcriptionService.progress
                    )

                case .transcribed:
                    if let transcript = recording.transcript {
                        TranscriptSection(transcript: transcript)

                        TranscriptQualityWarningView(transcript: transcript)

                        ActionPromptView(
                            title: "Ready for Analysis",
                            description: "Analyze this transcript for teaching technique feedback.",
                            buttonTitle: "Configure & Analyze",
                            isLoading: isProcessing,
                            action: { showingAnalysisConfig = true }
                        )
                    }

                case .analyzing:
                    if let transcript = recording.transcript {
                        TranscriptSection(transcript: transcript)
                    }

                    AnalyzingTimerView(
                        title: recording.isVideo && recording.transcript == nil ? "Analyzing Video..." : "Analyzing..."
                    )

                case .complete:
                    if let analysis = recording.analysis {
                        if recording.reflection == nil {
                            // First visit: show reflection flow
                            ReflectionFlowView(
                                recording: recording,
                                analysis: analysis,
                                onComplete: { },
                                onSkip: { }
                            )
                        } else {
                            // Reflection done: show comparison (if completed, not skipped) + full feedback
                            if let reflection = recording.reflection,
                               reflection.isComplete, !reflection.wasSkipped {
                                ReflectionComparisonView(reflection: reflection, analysis: analysis)
                            }
                            AnalysisFeedbackView(analysis: analysis, recording: recording)
                        }
                    }

                    if let transcript = recording.transcript {
                        TranscriptSection(transcript: transcript, collapsed: true)
                    }

                case .recording, .failed:
                    if recording.status == .failed {
                        FailedRecordingView()
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(recording.title)
        .toolbar {
            ToolbarItemGroup {
                if recording.status == .complete {
                    Button {
                        showingExportConfig = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isProcessing)
                }

                if recording.status == .transcribed || recording.status == .complete {
                    Button {
                        // Re-analyze
                        startAnalysis()
                    } label: {
                        Label("Re-analyze", systemImage: "arrow.clockwise")
                    }
                    .disabled(isProcessing)
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .alert("Delete Recording?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecording()
            }
        } message: {
            Text("This will permanently delete the recording and all associated data.")
        }
        .sheet(isPresented: $showingAnalysisConfig) {
            AnalysisConfigurationSheet { framework, techniqueIds, includeRatings in
                startAnalysis(framework: framework, techniqueIds: techniqueIds, includeRatings: includeRatings)
            }
        }
        .sheet(isPresented: $showingExportConfig) {
            if let analysis = recording.analysis {
                ExportConfigurationSheet(
                    analysis: analysis,
                    recording: recording
                ) { configuration in
                    exportAnalysis(configuration: configuration)
                }
            }
        }
        .sheet(isPresented: $showingVideoAnalysisConfig) {
            VideoAnalysisConfigurationSheet { framework, techniqueIds, includeRatings in
                startVideoAnalysis(framework: framework, techniqueIds: techniqueIds, includeRatings: includeRatings)
            }
        }
    }

    // MARK: - Actions

    private func startTranscription() {
        isProcessing = true
        recording.status = .transcribing

        Task {
            do {
                try modelContext.save()

                let transcript = try await services.transcriptionService.transcribe(recording: recording)

                // Save transcript
                recording.transcript = transcript
                recording.status = .transcribed
                try modelContext.save()

            } catch {
                recording.status = .recorded
                appState.handleError(.transcription(.processingFailed(error)))
            }

            isProcessing = false
        }
    }

    private func startAnalysis(framework: TeachingFramework, techniqueIds: [String], includeRatings: Bool = true) {
        guard let transcript = recording.transcript else { return }

        isProcessing = true
        recording.status = .analyzing

        Task {
            do {
                let session = try await services.authService.getValidSession(updating: appState)
                try modelContext.save()

                // Get enabled techniques for the selected framework
                let techniques = services.techniqueService.getEnabledTechniques(
                    for: framework,
                    enabledIds: techniqueIds
                )

                let analysis = try await services.analysisService.analyze(
                    transcript: transcript,
                    techniques: techniques,
                    sessionToken: session.accessToken,
                    includeRatings: includeRatings
                )

                // Clear stale reflection and chat session on re-analysis
                recording.reflection = nil
                recording.chatSessions = []

                // Save analysis
                analysis.frameworkId = framework.rawValue
                recording.analysis = analysis
                recording.status = .complete
                try modelContext.save()

            } catch AuthError.cancelled {
                recording.status = .transcribed
            } catch {
                recording.status = .transcribed
                appState.handleError(.analysis(.apiError(500, error.localizedDescription)))
            }

            isProcessing = false
        }
    }

    /// Legacy method for re-analysis from toolbar
    private func startAnalysis() {
        // Load the saved framework and technique preferences
        guard let email = appState.currentUser?.email else { return }

        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.userEmail == email }
        )

        if let settings = try? modelContext.fetch(descriptor).first {
            let framework = settings.selectedFramework
            let techniqueIds = settings.enabledTechniqueIds(for: framework)
            let includeRatings = settings.includeRatingsInAnalysis
            startAnalysis(framework: framework, techniqueIds: techniqueIds, includeRatings: includeRatings)
        } else {
            // Default to TLAC with all techniques and ratings enabled
            startAnalysis(framework: .tlac, techniqueIds: FrameworkRegistry.defaultEnabledIds(for: .tlac), includeRatings: true)
        }
    }

    private func deleteRecording() {
        services.recordingService.deleteAudioFile(for: recording)
        modelContext.delete(recording)
        try? modelContext.save()
    }

    private func startVideoAnalysis(framework: TeachingFramework, techniqueIds: [String], includeRatings: Bool = true) {
        guard let videoURL = recording.absoluteVideoPath else { return }

        isProcessing = true
        recording.status = .uploading

        Task {
            do {
                let session = try await services.authService.getValidSession(updating: appState)
                try modelContext.save()

                // Get enabled techniques for the selected framework
                let techniques = services.techniqueService.getEnabledTechniques(
                    for: framework,
                    enabledIds: techniqueIds
                )

                recording.status = .analyzing
                try modelContext.save()

                // Run video analysis and transcript extraction in parallel
                async let analysisResult = services.videoAnalysisService.analyzeVideo(
                    videoURL: videoURL,
                    techniques: techniques,
                    sessionToken: session.accessToken,
                    includeRatings: includeRatings
                )
                async let transcriptResult = extractAndTranscribe(videoURL: videoURL)

                let analysis = try await analysisResult
                let transcript = try? await transcriptResult  // Don't fail if transcription fails

                // Clear stale reflection and chat session on re-analysis
                recording.reflection = nil
                recording.chatSessions = []

                // Save analysis (required) and transcript (best-effort)
                analysis.frameworkId = framework.rawValue
                recording.analysis = analysis
                recording.transcript = transcript
                recording.status = .complete
                try modelContext.save()

            } catch AuthError.cancelled {
                recording.status = .recorded
            } catch {
                recording.status = .recorded
                appState.handleError(.videoAnalysisError(.apiError(500, error.localizedDescription)))
            }

            isProcessing = false
        }
    }

    /// Extract audio from video and transcribe it, returning the transcript
    private func extractAndTranscribe(videoURL: URL) async throws -> Transcript {
        let audioURL = try await services.audioExtractionService.extractAudio(from: videoURL)
        recording.audioFilePath = audioURL.lastPathComponent
        return try await services.transcriptionService.transcribe(recording: recording)
    }

    private func startAudioExtractionAndTranscription() {
        guard recording.isVideo,
              let videoURL = recording.absoluteVideoPath else {
            return
        }

        isProcessing = true
        recording.status = .transcribing

        Task {
            do {
                try modelContext.save()

                // Extract audio from video
                let audioURL = try await services.audioExtractionService.extractAudio(from: videoURL)

                // Update recording with extracted audio path
                recording.audioFilePath = audioURL.lastPathComponent

                // Transcribe the extracted audio
                let transcript = try await services.transcriptionService.transcribe(recording: recording)

                // Save transcript
                recording.transcript = transcript
                recording.status = .transcribed
                try modelContext.save()

            } catch {
                recording.status = .recorded
                appState.handleError(.transcription(.processingFailed(error)))
            }

            isProcessing = false
        }
    }

    private func exportAnalysis(configuration: ExportConfiguration) {
        guard let analysis = recording.analysis else { return }

        Task {
            do {
                let url = try await services.exportService.export(
                    analysis: analysis,
                    recording: recording,
                    configuration: configuration
                )
                print("Exported to: \(url)")
            } catch ExportService.ExportError.saveCancelled {
                // User cancelled, no error to show
            } catch {
                print("Export error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Recording Header

struct RecordingHeaderView: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recording.title)
                    .font(PSDFonts.title)
                    .foregroundStyle(.primary)

                Spacer()

                if recording.isVideo {
                    MediaTypeBadge(mediaType: .video)
                }

                StatusBadge(status: recording.status)
            }

            HStack(spacing: 16) {
                Label(recording.formattedDuration, systemImage: "clock")
                Label {
                    Text(recording.createdAt, format: .dateTime.month().day().year())
                } icon: {
                    Image(systemName: "calendar")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Action Prompt View

struct ActionPromptView: View {
    let title: String
    let description: String
    let buttonTitle: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(PSDFonts.headline)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                action()
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(buttonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    let title: String
    let progress: Double

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)

            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Analyzing Timer View

struct AnalyzingTimerView: View {
    let title: String

    @State private var elapsedSeconds: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            ProgressView()
                .controlSize(.small)

            Text(title)
                .font(.headline)

            Spacer()

            Text(formattedTime)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onReceive(timer) { _ in
            elapsedSeconds += 1
        }
    }

    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Transcript Section

struct TranscriptSection: View {
    let transcript: Transcript
    var collapsed: Bool = false

    @State private var isExpanded = true
    @State private var showPauses = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Transcript")
                        .font(PSDFonts.headline)

                    Spacer()

                    Text("\(transcript.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Pause Summary (if pauses exist)
                if !transcript.pauses.isEmpty {
                    PauseSummaryView(pauses: transcript.pauses, recordingDuration: transcript.recording?.duration ?? 0)
                }

                // Transcript content with inline pause markers
                TranscriptContentView(transcript: transcript, showPauses: showPauses)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            isExpanded = !collapsed
        }
    }
}

// MARK: - Transcript Content View

struct TranscriptContentView: View {
    let transcript: Transcript
    let showPauses: Bool

    var body: some View {
        Group {
            if showPauses && !transcript.pauses.isEmpty {
                // Use flow layout with interleaved pause markers
                flowLayoutContent
            } else {
                // Segment-based display with timestamps
                segmentContent
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var segmentContent: some View {
        let segments = transcript.segments.sorted { $0.startTime < $1.startTime }

        if segments.isEmpty {
            Text(transcript.fullText)
                .font(.body)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(segments) { segment in
                    HStack(alignment: .top, spacing: 8) {
                        Text(formatStartTime(segment.startTime))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                        Text(segment.text)
                            .font(.body)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var flowLayoutContent: some View {
        let items = buildTranscriptItems()

        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                switch item.type {
                case .segment(let text):
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.timestamp)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                        Text(text)
                            .font(.body)
                        if let pause = item.followingPause {
                            PauseMarkerView(pause: pause)
                        }
                    }
                }
            }
        }
    }

    private func buildTranscriptItems() -> [TranscriptItem] {
        let segments = transcript.segments.sorted { $0.startTime < $1.startTime }
        let pauses = transcript.pauses.sorted { $0.startTime < $1.startTime }

        var items: [TranscriptItem] = []
        var pauseIndex = 0

        for segment in segments {
            var followingPause: TranscriptPause? = nil

            // Check if there's a pause after this segment
            if pauseIndex < pauses.count {
                let pause = pauses[pauseIndex]
                if abs(pause.startTime - segment.endTime) < 0.5 {
                    followingPause = pause
                    pauseIndex += 1
                }
            }

            items.append(TranscriptItem(
                type: .segment(segment.text),
                timestamp: formatStartTime(segment.startTime),
                followingPause: followingPause
            ))
        }

        return items
    }

    private func formatStartTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct TranscriptItem: Identifiable {
    let id = UUID()
    let type: TranscriptItemType
    let timestamp: String
    let followingPause: TranscriptPause?

    init(type: TranscriptItemType, timestamp: String = "0:00", followingPause: TranscriptPause? = nil) {
        self.type = type
        self.timestamp = timestamp
        self.followingPause = followingPause
    }
}

enum TranscriptItemType {
    case segment(String)
}

// MARK: - Pause Marker View

struct PauseMarkerView: View {
    let pause: TranscriptPause

    var body: some View {
        Text("[\(pause.formattedDuration) pause]")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Pause Summary View

struct PauseSummaryView: View {
    let pauses: [TranscriptPause]
    let recordingDuration: TimeInterval

    private var totalPauseTime: TimeInterval {
        pauses.reduce(0) { $0 + $1.duration }
    }

    private var averageDuration: TimeInterval {
        guard !pauses.isEmpty else { return 0 }
        return totalPauseTime / Double(pauses.count)
    }

    private var maxDuration: TimeInterval {
        pauses.map(\.duration).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Wait Time Pauses", systemImage: "pause.circle")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(pauses.count) detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                PauseStatView(label: "Average", value: String(format: "%.1fs", averageDuration))
                PauseStatView(label: "Longest", value: String(format: "%.1fs", maxDuration))
                PauseStatView(label: "Total", value: String(format: "%.1fs", totalPauseTime))
            }

            // Timeline visualization
            if recordingDuration > 0 {
                PauseTimelineView(pauses: pauses, duration: recordingDuration)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PauseStatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Pause Timeline View

struct PauseTimelineView: View {
    let pauses: [TranscriptPause]
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(.secondary.opacity(0.2))
                    .frame(height: 8)

                // Pause markers
                ForEach(pauses) { pause in
                    let startPosition = (pause.startTime / duration) * geometry.size.width
                    let pauseWidth = max(4, (pause.duration / duration) * geometry.size.width)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(.orange)
                        .frame(width: pauseWidth, height: 8)
                        .offset(x: startPosition)
                }
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing

                self.size.width = max(self.size.width, currentX)
            }

            self.size.height = currentY + lineHeight
        }
    }
}

// MARK: - Failed Recording View

struct FailedRecordingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text("Recording Failed")
                .font(.headline)

            Text("There was an error processing this recording. Please try again.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Video Analysis Options View

struct VideoAnalysisOptionsView: View {
    let isProcessing: Bool
    let onVideoAnalysis: () -> Void
    let onAudioAnalysis: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Analysis Method")
                .font(PSDFonts.headline)

            Text("For best results and cost efficiency, we recommend clips of 5-20 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Video Analysis Option
            AnalysisMethodCard(
                title: "Video Analysis (Gemini)",
                description: "Analyzes visual + audio content. Observes teacher movements, student engagement, and classroom dynamics.",
                cost: "~$0.15-0.27 per analysis",
                icon: "video",
                isRecommended: true,
                isProcessing: isProcessing,
                action: onVideoAnalysis
            )

            // Audio Analysis Option
            AnalysisMethodCard(
                title: "Audio Only (Gemini)",
                description: "Extracts audio track and transcribes. Focuses on verbal communication and questioning techniques.",
                cost: "~$0.01-0.03 per analysis",
                icon: "waveform",
                isRecommended: false,
                isProcessing: isProcessing,
                action: onAudioAnalysis
            )
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AnalysisMethodCard: View {
    let title: String
    let description: String
    let cost: String
    let icon: String
    let isRecommended: Bool
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isRecommended ? PSDTheme.nextSteps : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PSDTheme.nextSteps.opacity(0.2))
                                .foregroundStyle(PSDTheme.nextSteps)
                                .clipShape(Capsule())
                        }
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    Text(cost)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(isRecommended ? PSDTheme.nextSteps.opacity(0.05) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }
}

// MARK: - Video Analysis Configuration Sheet

struct VideoAnalysisConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @State private var selectedFramework: TeachingFramework = .tlac
    @State private var enabledTechniqueIds: Set<String> = []
    @State private var includeRatings: Bool = true

    let onAnalyze: (TeachingFramework, [String], Bool) -> Void

    private var canStartAnalysis: Bool {
        !enabledTechniqueIds.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Configure Video Analysis")
                    .font(PSDFonts.headline)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Info banner
                    HStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .font(.title2)
                            .foregroundStyle(PSDTheme.infoBannerAccent)

                        Text("Video analysis uses Google Gemini to observe visual and audio content, providing feedback on teacher positioning, student engagement, and non-verbal cues.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(PSDTheme.infoBanner)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    FrameworkSelectionView(
                        selectedFramework: $selectedFramework,
                        enabledTechniqueIds: $enabledTechniqueIds
                    )

                    // Ratings toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Include Star Ratings", isOn: $includeRatings)
                        Text("When enabled, each technique receives a 1-5 star rating.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if includeRatings {
                            RatingLegendView(compact: false)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                if enabledTechniqueIds.isEmpty {
                    Text("Select at least one technique")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button("Start Video Analysis") {
                    savePreferences()
                    onAnalyze(selectedFramework, Array(enabledTechniqueIds), includeRatings)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartAnalysis)
            }
            .padding()
            .background(.bar)
        }
        .frame(width: 450, height: 550)
        .onAppear {
            loadUserPreferences()
        }
        .onChange(of: selectedFramework) { _, newFramework in
            enabledTechniqueIds = Set(loadEnabledIds(for: newFramework))
        }
    }

    private func loadUserPreferences() {
        guard let email = appState.currentUser?.email else {
            loadDefaultTechniques()
            return
        }

        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.userEmail == email }
        )

        if let settings = try? modelContext.fetch(descriptor).first {
            selectedFramework = settings.selectedFramework
            enabledTechniqueIds = Set(settings.enabledTechniqueIds(for: selectedFramework))
            includeRatings = settings.includeRatingsInAnalysis
        } else {
            loadDefaultTechniques()
        }
    }

    private func loadEnabledIds(for framework: TeachingFramework) -> [String] {
        guard let email = appState.currentUser?.email else {
            return FrameworkRegistry.defaultEnabledIds(for: framework)
        }

        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.userEmail == email }
        )

        if let settings = try? modelContext.fetch(descriptor).first {
            return settings.enabledTechniqueIds(for: framework)
        }

        return FrameworkRegistry.defaultEnabledIds(for: framework)
    }

    private func loadDefaultTechniques() {
        enabledTechniqueIds = Set(FrameworkRegistry.defaultEnabledIds(for: selectedFramework))
    }

    private func savePreferences() {
        guard let email = appState.currentUser?.email else { return }

        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.userEmail == email }
        )

        let settings: UserSettings
        if let existingSettings = try? modelContext.fetch(descriptor).first {
            settings = existingSettings
        } else {
            settings = UserSettings(userEmail: email)
            modelContext.insert(settings)
        }

        settings.selectedFramework = selectedFramework
        settings.setEnabledTechniqueIds(Array(enabledTechniqueIds), for: selectedFramework)
        settings.includeRatingsInAnalysis = includeRatings

        try? modelContext.save()
    }
}

// MARK: - Transcript Quality Warning View

struct TranscriptQualityWarningView: View {
    let transcript: Transcript

    private var averageConfidence: Float? {
        let confidences = transcript.segments.compactMap { $0.confidence }
        guard !confidences.isEmpty else { return nil }
        return confidences.reduce(0, +) / Float(confidences.count)
    }

    private var isShortTranscript: Bool {
        transcript.wordCount < 100
    }

    private var isLowConfidence: Bool {
        guard let avg = averageConfidence else { return false }
        return avg < 0.5
    }

    var body: some View {
        if isShortTranscript || isLowConfidence {
            VStack(alignment: .leading, spacing: 8) {
                Label("Transcript Quality", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)

                if isShortTranscript {
                    Text("This transcript has only \(transcript.wordCount) words. Short transcripts may produce vague feedback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isLowConfidence, let avg = averageConfidence {
                    Text("Average transcription confidence is \(Int(avg * 100))%. Low confidence may indicate poor audio quality.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    let recording = Recording(
        title: "Math Lesson",
        duration: 1800,
        audioFilePath: "test.m4a",
        status: .complete
    )

    return NavigationStack {
        RecordingDetailView(recording: recording)
    }
    .environmentObject(AppState())
    .environment(ServiceContainer.shared)
}
