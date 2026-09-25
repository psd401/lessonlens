import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .alert("Error", isPresented: $appState.showingError) {
            Button("OK") {
                appState.currentError = nil
            }
        } message: {
            if let error = appState.currentError {
                Text(error.localizedDescription)
            }
        }
        .onAppear {
            // Initialize techniques in database
            services.techniqueService.initializeTechniquesInDatabase(context: modelContext)
            // Migrate incomplete technique names from older analyses
            services.techniqueService.migrateIncompleteTeechniqueNames(context: modelContext)
        }
    }
}

// MARK: - Main View (Authenticated)

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    @State private var selectedRecording: Recording?
    @State private var showingNewRecording = false
    @State private var showingFileImporter = false
    @State private var showingVideoImporter = false
    @State private var showingGrowthDashboard = false
    @State private var showingFrameworkExplorer = false
    @State private var showingHowItWorks = false
    @State private var showingTermsAndPrivacy = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                recordings: recordings,
                selectedRecording: $selectedRecording,
                showingNewRecording: $showingNewRecording,
                showingGrowthDashboard: $showingGrowthDashboard,
                showingFrameworkExplorer: $showingFrameworkExplorer,
                showingHowItWorks: $showingHowItWorks,
                showingTermsAndPrivacy: $showingTermsAndPrivacy
            )
        } detail: {
            if let recording = selectedRecording {
                RecordingDetailView(recording: recording, onReanalyze: { selectedRecording = $0 })
            } else if showingTermsAndPrivacy {
                TermsAndPrivacyView()
            } else if showingHowItWorks {
                HowItWorksView()
            } else if showingFrameworkExplorer {
                FrameworkExplorerView()
            } else if showingGrowthDashboard {
                GrowthDashboardView()
            } else if showingNewRecording {
                NewRecordingView(
                    isPresented: $showingNewRecording,
                    onComplete: { recording in
                        selectedRecording = recording
                        showingNewRecording = false
                    }
                )
            } else {
                WelcomeView(showingNewRecording: $showingNewRecording) { recording in
                    selectedRecording = recording
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingNewRecording = true
                        selectedRecording = nil
                    } label: {
                        Label("New Recording", systemImage: "record.circle")
                    }

                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Import Audio", systemImage: "waveform")
                    }

                    Button {
                        showingVideoImporter = true
                    } label: {
                        Label("Import Video", systemImage: "video")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: AudioImportService.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingVideoImporter) {
            VideoImportView { recording in
                selectedRecording = recording
                showingNewRecording = false
            }
        }
        .onChange(of: selectedRecording) { _, newValue in
            if newValue != nil {
                showingGrowthDashboard = false
                showingFrameworkExplorer = false
                showingHowItWorks = false
                showingTermsAndPrivacy = false
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let recording = try await services.audioImportService.importAudioFile(from: url)
                    modelContext.insert(recording)
                    selectedRecording = recording
                    showingNewRecording = false
                } catch let error as ImportError {
                    appState.handleError(.importError(error))
                } catch {
                    appState.handleError(.importError(.copyFailed(error)))
                }
            }
        case .failure(let error):
            appState.handleError(.importError(.copyFailed(error)))
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    let recordings: [Recording]
    @Binding var selectedRecording: Recording?
    @Binding var showingNewRecording: Bool
    @Binding var showingGrowthDashboard: Bool
    @Binding var showingFrameworkExplorer: Bool
    @Binding var showingHowItWorks: Bool
    @Binding var showingTermsAndPrivacy: Bool

    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @State private var recordingToRename: Recording?
    @State private var renameText = ""

    var body: some View {
        List(selection: $selectedRecording) {
            // Home button
            Button {
                selectedRecording = nil
                showingNewRecording = false
                showingGrowthDashboard = false
                showingFrameworkExplorer = false
                showingHowItWorks = false
                showingTermsAndPrivacy = false
            } label: {
                Label("Home", systemImage: "house")
                    .font(PSDFonts.headline)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            // Growth button
            Button {
                selectedRecording = nil
                showingNewRecording = false
                showingFrameworkExplorer = false
                showingHowItWorks = false
                showingTermsAndPrivacy = false
                showingGrowthDashboard = true
            } label: {
                Label("Growth", systemImage: "chart.line.uptrend.xyaxis")
                    .font(PSDFonts.headline)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            // Frameworks button
            Button {
                selectedRecording = nil
                showingNewRecording = false
                showingGrowthDashboard = false
                showingHowItWorks = false
                showingTermsAndPrivacy = false
                showingFrameworkExplorer = true
            } label: {
                Label("Frameworks", systemImage: "book.pages")
                    .font(PSDFonts.headline)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            // How It Works button
            Button {
                selectedRecording = nil
                showingNewRecording = false
                showingGrowthDashboard = false
                showingFrameworkExplorer = false
                showingTermsAndPrivacy = false
                showingHowItWorks = true
            } label: {
                Label("How It Works", systemImage: "questionmark.circle")
                    .font(PSDFonts.headline)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            Section("Sessions") {
                ForEach(recordings) { recording in
                    RecordingRowView(recording: recording)
                        .tag(recording)
                        .contextMenu {
                            Button {
                                renameText = recording.title
                                recordingToRename = recording
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 250)
        .safeAreaInset(edge: .bottom) {
            Button {
                selectedRecording = nil
                showingNewRecording = false
                showingGrowthDashboard = false
                showingFrameworkExplorer = false
                showingHowItWorks = false
                showingTermsAndPrivacy = true
            } label: {
                Label("Terms & Privacy", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Sign Out") {
                        appState.signOut()
                    }
                } label: {
                    Label(
                        appState.currentUser?.displayName ?? "Account",
                        systemImage: "person.circle"
                    )
                }
            }
        }
        .navigationTitle("LessonLens")
        .alert("Rename Session", isPresented: .init(
            get: { recordingToRename != nil },
            set: { if !$0 { recordingToRename = nil } }
        )) {
            TextField("Session name", text: $renameText)
            Button("Cancel", role: .cancel) {
                recordingToRename = nil
            }
            Button("Rename") {
                if let recording = recordingToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    recording.title = renameText.trimmingCharacters(in: .whitespaces)
                    try? modelContext.save()
                }
                recordingToRename = nil
            }
        } message: {
            Text("Enter a new name for this session.")
        }
    }
}

// MARK: - Recording Row

struct RecordingRowView: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.headline)

            HStack {
                Text(recording.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if recording.isVideo {
                    MediaTypeBadge(mediaType: .video)
                }

                if recording.isImported {
                    ImportedBadge()
                }

                StatusBadge(status: recording.status)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Media Type Badge

struct MediaTypeBadge: View {
    let mediaType: MediaType

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: mediaType == .video ? "video" : "waveform")
                .font(.caption2)
            Text(mediaType == .video ? "Video" : "Audio")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(mediaType == .video ? PSDTheme.video.opacity(0.2) : PSDTheme.audio.opacity(0.2))
        .foregroundStyle(mediaType == .video ? PSDTheme.video : PSDTheme.audio)
        .clipShape(Capsule())
    }
}

// MARK: - Imported Badge

struct ImportedBadge: View {
    var body: some View {
        Text("Imported")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.2))
            .foregroundStyle(.gray)
            .clipShape(Capsule())
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: RecordingStatus

    var body: some View {
        Text(status.displayText)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .recording: return PSDTheme.recording.opacity(0.2)
        case .recorded: return PSDTheme.growth.opacity(0.2)
        case .uploading, .transcribing, .analyzing: return PSDTheme.processing.opacity(0.2)
        case .transcribed: return PSDTheme.processing.opacity(0.2)
        case .complete: return PSDTheme.success.opacity(0.2)
        case .failed: return PSDTheme.error.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .recording: return PSDTheme.recording
        case .recorded: return PSDTheme.growth
        case .uploading, .transcribing, .analyzing: return PSDTheme.processing
        case .transcribed: return PSDTheme.processing
        case .complete: return PSDTheme.success
        case .failed: return PSDTheme.error
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @Binding var showingNewRecording: Bool
    var onImportComplete: ((Recording) -> Void)?
    @EnvironmentObject private var appState: AppState
    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingFileImporter = false
    @State private var showingVideoImporter = false

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                LessonLensLogoView(size: 80)

                Text("Welcome, \(appState.currentUser?.displayName.components(separatedBy: " ").first ?? "Teacher")!")
                    .font(PSDFonts.largeTitle)
                    .foregroundStyle(PSDTheme.headingText(for: colorScheme))

                Text("Record, reflect, and grow with AI-powered coaching.")
                    .font(PSDFonts.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 450)
            }

            // Action Tiles
            LazyVGrid(columns: columns, spacing: 16) {
                ActionTile(
                    title: "New Recording",
                    subtitle: "Record a lesson",
                    icon: "record.circle.fill",
                    color: PSDTheme.recording
                ) {
                    showingNewRecording = true
                }

                ActionTile(
                    title: "Import Audio",
                    subtitle: "Voice memo or audio",
                    icon: "waveform",
                    color: PSDTheme.audio
                ) {
                    showingFileImporter = true
                }

                ActionTile(
                    title: "Import Video",
                    subtitle: "Classroom recording",
                    icon: "video.fill",
                    color: PSDTheme.video
                ) {
                    showingVideoImporter = true
                }
            }
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .psdPageBackground()
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: AudioImportService.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingVideoImporter) {
            VideoImportView { recording in
                onImportComplete?(recording)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let recording = try await services.audioImportService.importAudioFile(from: url)
                    modelContext.insert(recording)
                    onImportComplete?(recording)
                } catch let error as ImportError {
                    appState.handleError(.importError(error))
                } catch {
                    appState.handleError(.importError(.copyFailed(error)))
                }
            }
        case .failure(let error):
            appState.handleError(.importError(.copyFailed(error)))
        }
    }
}

// MARK: - Action Tile

struct ActionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(color)

                VStack(spacing: 4) {
                    Text(title)
                        .font(PSDFonts.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(isHovering ? 0.15 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(isHovering ? 0.4 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environment(ServiceContainer.shared)
}
