import SwiftUI
import SwiftData

/// Pre-analysis modal for configuring framework and technique selection
struct AnalysisConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    /// Callback when user confirms analysis (framework, techniqueIds, includeRatings)
    let onStartAnalysis: (TeachingFramework, [String], Bool) -> Void

    @State private var selectedFramework: TeachingFramework = .tlac
    @State private var enabledTechniqueIds: Set<String> = []
    @State private var includeRatings = true
    @State private var isLoading = true

    private var canStartAnalysis: Bool {
        !enabledTechniqueIds.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Configure Analysis")
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
                    .padding(16)
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

                Button("Start Analysis") {
                    savePreferences()
                    onStartAnalysis(selectedFramework, Array(enabledTechniqueIds), includeRatings)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartAnalysis)
            }
            .padding()
            .background(.bar)
        }
        .onAppear {
            loadPreferences()
        }
        .onChange(of: selectedFramework) { _, newFramework in
            // Load technique selections for the new framework
            enabledTechniqueIds = Set(loadEnabledIds(for: newFramework))
        }
    }

    // MARK: - Settings Persistence

    private func loadPreferences() {
        guard let email = appState.currentUser?.email else {
            setDefaults()
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
            setDefaults()
        }

        isLoading = false
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

    private func setDefaults() {
        selectedFramework = .tlac
        enabledTechniqueIds = Set(FrameworkRegistry.defaultEnabledIds(for: .tlac))
        includeRatings = true
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

#Preview {
    AnalysisConfigurationSheet { framework, techniqueIds, includeRatings in
        print("Start analysis with \(framework.displayName), \(techniqueIds.count) techniques, ratings: \(includeRatings)")
    }
    .environmentObject(AppState())
    .environment(ServiceContainer.shared)
}
