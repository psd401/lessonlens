import SwiftUI

/// Modal for configuring export options
struct ExportConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.serviceContainer) private var services

    let analysis: Analysis
    let recording: Recording
    let onExport: (ExportConfiguration) -> Void

    @State private var configuration = ExportConfiguration()
    @State private var isExporting = false

    private var techniques: [TechniqueEvaluation] {
        analysis.techniqueEvaluations ?? []
    }

    private var allTechniqueIds: Set<UUID> {
        Set(techniques.map { $0.id })
    }

    private var allTechniquesSelected: Bool {
        configuration.includedTechniqueIds == allTechniqueIds
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Analysis")
                    .font(.headline)

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
                    // Format Selection
                    formatSection

                    // Sections Selection
                    sectionsSelection

                    // Techniques Selection
                    if !techniques.isEmpty {
                        techniquesSelection
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                if !configuration.hasSelection {
                    Text("Select at least one item")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    isExporting = true
                    onExport(configuration)
                    dismiss()
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Export \(configuration.format.rawValue)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!configuration.hasSelection || isExporting)
            }
            .padding()
            .background(.bar)
        }
        .onAppear {
            // Initialize with all techniques selected
            configuration.includedTechniqueIds = allTechniqueIds
        }
    }

    // MARK: - Format Section

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("Format", selection: $configuration.format) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sections Selection

    private var sectionsSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Include Sections")
                .font(.subheadline)
                .fontWeight(.medium)

            Toggle("Summary", isOn: $configuration.includeSummary)
            Toggle("Strengths", isOn: $configuration.includeStrengths)
            Toggle("Growth Areas", isOn: $configuration.includeGrowthAreas)
            Toggle("Next Steps", isOn: $configuration.includeNextSteps)

            if recording.reflection != nil && recording.reflection?.isComplete == true {
                Toggle("Self-Reflection", isOn: $configuration.includeReflection)
            }

            if recording.transcript != nil {
                Toggle("Transcript", isOn: $configuration.includeTranscript)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Techniques Selection

    private var techniquesSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Technique Feedback")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Button(allTechniquesSelected ? "Deselect All" : "Select All") {
                    if allTechniquesSelected {
                        configuration.includedTechniqueIds = []
                    } else {
                        configuration.includedTechniqueIds = allTechniqueIds
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(PSDTheme.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(techniques) { technique in
                    Toggle(isOn: Binding(
                        get: { configuration.includedTechniqueIds.contains(technique.id) },
                        set: { isSelected in
                            if isSelected {
                                configuration.includedTechniqueIds.insert(technique.id)
                            } else {
                                configuration.includedTechniqueIds.remove(technique.id)
                            }
                        }
                    )) {
                        HStack {
                            Text(technique.techniqueName)
                                .lineLimit(1)

                            if analysis.ratingsIncluded, let rating = technique.rating {
                                Spacer()
                                RatingBadge(rating: rating)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    let analysis = Analysis(
        overallSummary: "Test summary",
        modelUsed: "gemini-3-pro-preview",
        strengths: ["Strength 1"],
        growthAreas: ["Growth 1"],
        actionableNextSteps: ["Step 1"]
    )

    let recording = Recording(
        title: "Math Lesson",
        duration: 1800,
        audioFilePath: "test.m4a",
        status: .complete
    )

    return ExportConfigurationSheet(
        analysis: analysis,
        recording: recording
    ) { config in
        print("Export with config: \(config)")
    }
}
