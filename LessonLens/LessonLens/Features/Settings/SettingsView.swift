import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext

    @State private var settings: UserSettings?
    @State private var showTimestamps = true
    @State private var selectedFramework: TeachingFramework = .tlac
    @State private var enabledTechniqueIds: Set<String> = []

    var body: some View {
        TabView {
            GeneralSettingsTab(
                showTimestamps: $showTimestamps
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            TechniquesSettingsTab(
                selectedFramework: $selectedFramework,
                enabledTechniqueIds: $enabledTechniqueIds
            )
            .tabItem {
                Label("Techniques", systemImage: "list.bullet.clipboard")
            }

            AccountSettingsTab()
            .tabItem {
                Label("Account", systemImage: "person.circle")
            }

            AboutTab()
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loadSettings()
        }
        .onChange(of: showTimestamps) { _, _ in saveSettings() }
        .onChange(of: selectedFramework) { oldValue, newValue in
            // Load technique IDs for new framework
            if let settings = settings {
                enabledTechniqueIds = Set(settings.enabledTechniqueIds(for: newValue))
            } else {
                enabledTechniqueIds = Set(FrameworkRegistry.defaultEnabledIds(for: newValue))
            }
            saveSettings()
        }
        .onChange(of: enabledTechniqueIds) { _, _ in saveSettings() }
    }

    private func loadSettings() {
        guard let email = appState.currentUser?.email else { return }

        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.userEmail == email }
        )

        if let existingSettings = try? modelContext.fetch(descriptor).first {
            settings = existingSettings
            showTimestamps = existingSettings.showTimestamps
            selectedFramework = existingSettings.selectedFramework
            enabledTechniqueIds = Set(existingSettings.enabledTechniqueIds(for: selectedFramework))
        } else {
            // Create default settings
            let newSettings = UserSettings(userEmail: email)
            modelContext.insert(newSettings)
            settings = newSettings
            selectedFramework = .tlac
            enabledTechniqueIds = Set(services.techniqueService.getDefaultEnabledIds(for: .tlac))
        }
    }

    private func saveSettings() {
        guard let settings = settings else { return }

        settings.showTimestamps = showTimestamps
        settings.selectedFramework = selectedFramework
        settings.setEnabledTechniqueIds(Array(enabledTechniqueIds), for: selectedFramework)

        try? modelContext.save()
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @Binding var showTimestamps: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var unusedFiles: [(name: String, bytes: Int64)] = []
    @State private var showingRemoveConfirmation = false
    @State private var cleanupMessage: String?

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show timestamps in transcript", isOn: $showTimestamps)
            }

            Section("Storage") {
                LabeledContent("Recordings Location") {
                    Text("~/Library/Application Support/com.peninsula.lessonlens/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Open Recordings Folder") {
                    openRecordingsFolder()
                }

                Button("Remove Unused Files…") {
                    findUnusedFiles()
                }
                .help("Removes recording files that no session uses, such as videos from sessions deleted before this was fixed")
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert(removeTitle, isPresented: $showingRemoveConfirmation) {
            Button("Remove", role: .destructive) { removeUnusedFiles() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These files aren't used by any session. This can't be undone.")
        }
        .alert(cleanupMessage ?? "", isPresented: Binding(
            get: { cleanupMessage != nil },
            set: { if !$0 { cleanupMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    private var removeTitle: String {
        let size = ByteCountFormatter.string(fromByteCount: unusedFiles.reduce(0) { $0 + $1.bytes }, countStyle: .file)
        return unusedFiles.count == 1 ? "Remove 1 unused file (\(size))?" : "Remove \(unusedFiles.count) unused files (\(size))?"
    }

    private func findUnusedFiles() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Sessions in a set-aside store still use files here; they'd look unused
        if PersistentStore.hasOtherStore(appSupport: appSupport) {
            cleanupMessage = "LessonLens has a set-aside copy of your sessions on this Mac, so it can't tell which files are unused. Nothing was removed."
            return
        }
        guard let files = Recording.unusedMediaFiles(in: modelContext) else {
            cleanupMessage = "The recordings folder couldn't be checked. Nothing was removed."
            return
        }
        if files.isEmpty {
            cleanupMessage = "There are no unused files."
            return
        }
        unusedFiles = files
        showingRemoveConfirmation = true
    }

    private func removeUnusedFiles() {
        let removed = Recording.removeUnreferencedMedia(unusedFiles.map(\.name), in: modelContext)
        cleanupMessage = removed.count == 1 ? "Removed 1 file." : "Removed \(removed.count) files."
        unusedFiles = []
    }

    private func openRecordingsFolder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordingsDir = appSupport
            .appendingPathComponent("com.peninsula.lessonlens")
            .appendingPathComponent("Recordings")

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: recordingsDir.path)
    }
}

// MARK: - Techniques Settings Tab

struct TechniquesSettingsTab: View {
    @Binding var selectedFramework: TeachingFramework
    @Binding var enabledTechniqueIds: Set<String>

    @Environment(\.serviceContainer) private var services

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Framework selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Teaching Framework")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Framework", selection: $selectedFramework) {
                    ForEach(TeachingFramework.allCases) { framework in
                        Text(framework.displayName).tag(framework)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedFramework.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Divider()

            Text("Select techniques to include in analysis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            List {
                ForEach(services.techniqueService.getTechniquesByCategory(for: selectedFramework), id: \.category) { group in
                    Section(group.category.rawValue) {
                        ForEach(group.techniques) { technique in
                            TechniqueToggleRow(
                                technique: technique,
                                isEnabled: enabledTechniqueIds.contains(technique.id),
                                onToggle: {
                                    if enabledTechniqueIds.contains(technique.id) {
                                        enabledTechniqueIds.remove(technique.id)
                                    } else {
                                        enabledTechniqueIds.insert(technique.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }

            HStack {
                Button("Select All") {
                    let allIds = services.techniqueService.getTechniques(for: selectedFramework).map { $0.id }
                    enabledTechniqueIds = Set(allIds)
                }

                Button("Deselect All") {
                    enabledTechniqueIds = []
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

struct TechniqueToggleRow: View {
    let technique: Technique
    let isEnabled: Bool
    let onToggle: () -> Void

    @State private var showingDetail = false

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            )) {
                VStack(alignment: .leading) {
                    Text(technique.name)
                        .font(.body)

                    Text(technique.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Button {
                showingDetail = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDetail) {
                TechniqueDetailPopover(technique: technique)
            }
        }
    }
}

struct TechniqueDetailPopover: View {
    let technique: Technique

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(technique.name)
                .font(.headline)

            Text(technique.descriptionText)
                .font(.body)

            if !technique.lookFors.isEmpty {
                Text("Look-fors:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                ForEach(technique.lookFors, id: \.self) { item in
                    Text("• \(item)")
                        .font(.caption)
                }
            }

            if !technique.exemplarPhrases.isEmpty {
                Text("Example phrases:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                ForEach(technique.exemplarPhrases.prefix(3), id: \.self) { phrase in
                    Text("\"\(phrase)\"")
                        .font(.caption)
                        .italic()
                }
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Account Settings Tab

struct AccountSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Signed In As") {
                if let user = appState.currentUser {
                    LabeledContent("Name") {
                        Text(user.displayName)
                    }

                    LabeledContent("Email") {
                        Text(user.email)
                    }
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    appState.signOut()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 24) {
            LessonLensLogoView(size: 80)

            VStack(spacing: 4) {
                Text("LessonLens")
                    .font(PSDFonts.title)

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Self-reflection and AI-powered coaching for teaching techniques")
                .font(PSDFonts.body())
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 8) {
                Text("Peninsula School District")
                    .font(PSDFonts.headline)

                Text("Research & Assessment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 6) {
                Text("Powered by WhisperKit and Gemini")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    PSDLogoView(size: 16)
                    Text("Brought to you by Peninsula School District")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environment(ServiceContainer.shared)
}
