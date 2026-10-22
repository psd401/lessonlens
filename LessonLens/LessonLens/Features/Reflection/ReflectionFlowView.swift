import SwiftUI
import SwiftData

/// Multi-step reflection wizard shown inline before AI feedback
struct ReflectionFlowView: View {
    @Bindable var recording: Recording
    let analysis: Analysis
    let onComplete: () -> Void
    let onSkip: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @State private var currentStep = 0
    @State private var whatWentWell = ""
    @State private var whatToChange = ""
    @State private var selfRatings: [TechniqueSelfRating] = []
    @State private var focusTechniqueIds: Set<String> = []

    private let totalSteps = 5

    /// All technique evaluations from the analysis (including unobserved)
    private var techniqueEvaluations: [TechniqueEvaluation] {
        analysis.techniqueEvaluations ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            reflectionHeader

            // Step content
            switch currentStep {
            case 0: whatWentWellStep
            case 1: whatToChangeStep
            case 2: selfRatingStep
            case 3: focusTechniqueStep
            case 4: reviewStep
            default: EmptyView()
            }

            // Navigation buttons
            navigationButtons
        }
        .psdCard()
        .onAppear {
            initializeSelfRatings()
        }
    }

    // MARK: - Header

    private var reflectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Self-Reflection", systemImage: "person.crop.circle.badge.checkmark")
                    .font(PSDFonts.headline)

                Spacer()

                Text("Step \(currentStep + 1) of \(totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(0.2))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(PSDTheme.accent)
                        .frame(width: geometry.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 4)
                }
            }
            .frame(height: 4)

            Text("Reflect on your lesson before viewing AI feedback.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 1: What Went Well

    private var whatWentWellStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What went well in this lesson?")
                .font(PSDFonts.headline)

            TextEditor(text: $whatWentWell)
                .frame(minHeight: 120)
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.3), lineWidth: 1)
                )

            Text("Consider student engagement, pacing, technique execution, and learning outcomes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2: What To Change

    private var whatToChangeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What would you change next time?")
                .font(PSDFonts.headline)

            TextEditor(text: $whatToChange)
                .frame(minHeight: 120)
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.3), lineWidth: 1)
                )

            Text("Think about what you would do differently to improve student learning.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 3: Self-Ratings

    private var selfRatingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rate your use of each technique")
                .font(PSDFonts.headline)

            Text("How well did you implement each technique during this lesson?")
                .font(.caption)
                .foregroundStyle(.secondary)

            RatingLegendView(compact: true)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach($selfRatings) { $rating in
                        SelfRatingPicker(
                            techniqueName: rating.techniqueName,
                            rating: $rating.rating
                        )
                        .padding()
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: - Step 4: Focus Techniques

    private var focusTechniqueStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose 1-2 techniques to focus on")
                .font(PSDFonts.headline)

            Text("Which techniques do you want to prioritize for growth?")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(selfRatings) { rating in
                    Button {
                        toggleFocusTechnique(rating.techniqueId)
                    } label: {
                        HStack {
                            Image(systemName: focusTechniqueIds.contains(rating.techniqueId) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(focusTechniqueIds.contains(rating.techniqueId) ? PSDTheme.accent : .secondary)

                            Text(rating.techniqueName)
                                .foregroundStyle(.primary)

                            Spacer()

                            if let level = RatingLevel(rawValue: rating.rating) {
                                RatingBadge(rating: level.rawValue)
                            }
                        }
                        .padding()
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            if focusTechniqueIds.count > 2 {
                Text("Select up to 2 techniques for focused growth.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Step 5: Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Your Reflection")
                .font(PSDFonts.headline)

            // What went well
            VStack(alignment: .leading, spacing: 4) {
                Text("What went well")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(whatWentWell.isEmpty ? "No response" : whatWentWell)
                    .font(.body)
                    .foregroundStyle(whatWentWell.isEmpty ? .secondary : .primary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PSDTheme.strength.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // What to change
            VStack(alignment: .leading, spacing: 4) {
                Text("What to change")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(whatToChange.isEmpty ? "No response" : whatToChange)
                    .font(.body)
                    .foregroundStyle(whatToChange.isEmpty ? .secondary : .primary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PSDTheme.growth.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Self-ratings summary
            if !selfRatings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Self-Ratings")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(selfRatings) { rating in
                        HStack {
                            Text(rating.techniqueName)
                                .font(.caption)
                            Spacer()
                            RatingBadge(rating: rating.rating)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Focus techniques
            if !focusTechniqueIds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Focus Techniques")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(selfRatings.filter { focusTechniqueIds.contains($0.techniqueId) }) { rating in
                        Label(rating.techniqueName, systemImage: "target")
                            .font(.body)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PSDTheme.nextSteps.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            // Skip button (visible on every step)
            Button("Skip to Feedback") {
                skipReflection()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)

            Spacer()

            if currentStep > 0 {
                Button("Back") {
                    withAnimation {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.bordered)
            }

            if currentStep < totalSteps - 1 {
                Button("Next") {
                    withAnimation {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Submit Reflection") {
                    submitReflection()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func initializeSelfRatings() {
        guard selfRatings.isEmpty else { return }
        selfRatings = techniqueEvaluations.map { eval in
            TechniqueSelfRating(
                techniqueId: eval.techniqueId,
                techniqueName: eval.techniqueName,
                rating: 3  // Default to established
            )
        }
    }

    private func toggleFocusTechnique(_ id: String) {
        if focusTechniqueIds.contains(id) {
            focusTechniqueIds.remove(id)
        } else if focusTechniqueIds.count < 2 {
            focusTechniqueIds.insert(id)
        }
    }

    private func submitReflection() {
        let reflection = Reflection(
            whatWentWell: whatWentWell,
            whatToChange: whatToChange,
            isComplete: true,
            wasSkipped: false,
            selfRatings: selfRatings,
            focusTechniqueIds: Array(focusTechniqueIds)
        )

        modelContext.insert(reflection)
        recording.reflection = reflection
        do {
            try modelContext.save()
        } catch {
            appState.handleError(.storage(.saveFailed(what: "your reflection")))
        }
        onComplete()
    }

    private func skipReflection() {
        let reflection = Reflection(
            isComplete: false,
            wasSkipped: true
        )

        modelContext.insert(reflection)
        recording.reflection = reflection
        try? modelContext.save()  // best-effort; only records that reflection was skipped
        onSkip()
    }
}
