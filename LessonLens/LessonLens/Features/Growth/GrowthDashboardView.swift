import SwiftUI
import SwiftData

struct GrowthDashboardView: View {
    @Query(sort: \Recording.createdAt) private var allRecordings: [Recording]

    @State private var selectedFramework: TeachingFramework = .tlac

    /// Recordings that are complete
    private var completedRecordings: [Recording] {
        allRecordings.filter { $0.status == .complete }
    }

    /// Recordings that have an analysis with the selected framework
    private var filteredRecordings: [Recording] {
        completedRecordings.filter { $0.analysis?.frameworkId == selectedFramework.rawValue }
    }

    /// Frameworks that have at least one completed analysis
    private var availableFrameworks: [TeachingFramework] {
        let frameworkIds = Set(completedRecordings.compactMap { $0.analysis?.frameworkId })
        return TeachingFramework.allCases.filter { frameworkIds.contains($0.rawValue) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Growth Dashboard")
                    .font(PSDFonts.largeTitle)
                    .foregroundStyle(.primary)

                if availableFrameworks.isEmpty {
                    emptyStateView
                } else {
                    // Framework filter
                    frameworkFilterSection

                    if filteredRecordings.isEmpty {
                        noRecordingsForFrameworkView
                    } else if filteredRecordings.count == 1 {
                        singleRecordingView
                    } else {
                        // Overall trend
                        OverallTrendSection(recordings: filteredRecordings)

                        // Technique breakdown
                        TechniqueBreakdownSection(recordings: filteredRecordings)

                        // Patterns & insights (Change D)
                        PatternsInsightsSection(recordings: filteredRecordings)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            // Default to first available framework
            if let first = availableFrameworks.first, !availableFrameworks.contains(selectedFramework) {
                selectedFramework = first
            }
        }
    }

    // MARK: - Framework Filter

    private var frameworkFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Framework")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Framework", selection: $selectedFramework) {
                ForEach(availableFrameworks) { framework in
                    Text(framework.shortName).tag(framework)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Complete your first analysis to start tracking growth")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var noRecordingsForFrameworkView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No analyses found for \(selectedFramework.shortName)")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var singleRecordingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Complete one more analysis with \(selectedFramework.shortName) to see trends")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Overall Trend Section

struct OverallTrendSection: View {
    let recordings: [Recording]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall Trend")
                .font(PSDFonts.headline)

            HStack(spacing: 8) {
                ForEach(recordings, id: \.id) { recording in
                    if let avg = recording.analysis?.averageRating {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(PSDTheme.ratingColor(Int(avg.rounded())))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Text(String(format: "%.1f", avg))
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                            Text(recording.createdAt, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Technique Breakdown Section

struct TechniqueBreakdownSection: View {
    let recordings: [Recording]

    /// All technique IDs across recordings, with their ratings grouped by recording date
    private var techniqueData: [(techniqueId: String, techniqueName: String, ratings: [(date: Date, rating: Int)])] {
        var dataMap: [String: (name: String, ratings: [(Date, Int)])] = [:]

        for recording in recordings {
            guard let evaluations = recording.analysis?.techniqueEvaluations else { continue }
            for eval in evaluations {
                guard let rating = eval.rating else { continue }
                var entry = dataMap[eval.techniqueId] ?? (name: eval.techniqueName, ratings: [])
                entry.ratings.append((recording.createdAt, rating))
                dataMap[eval.techniqueId] = entry
            }
        }

        return dataMap.map { (techniqueId: $0.key, techniqueName: $0.value.name, ratings: $0.value.ratings.sorted { $0.0 < $1.0 }) }
            .sorted { lhs, rhs in
                // Sort by lowest current rating first (needs attention at top)
                let lhsLast = lhs.ratings.last?.rating ?? 5
                let rhsLast = rhs.ratings.last?.rating ?? 5
                return lhsLast < rhsLast
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Technique Breakdown")
                .font(PSDFonts.headline)

            ForEach(techniqueData, id: \.techniqueId) { technique in
                HStack(spacing: 12) {
                    Text(technique.techniqueName)
                        .font(.subheadline)
                        .frame(width: 160, alignment: .leading)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        ForEach(technique.ratings.indices, id: \.self) { index in
                            let rating = technique.ratings[index].rating
                            Circle()
                                .fill(PSDTheme.ratingColor(rating))
                                .frame(width: 20, height: 20)
                                .overlay {
                                    Text("\(rating)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                        }
                    }

                    Spacer()
                }

                if technique.techniqueId != techniqueData.last?.techniqueId {
                    Divider()
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Patterns & Insights Section (Change D)

struct PatternsInsightsSection: View {
    let recordings: [Recording]

    private var patterns: [GrowthPattern] {
        GrowthPatternAnalyzer.analyze(recordings: recordings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Patterns & Insights")
                .font(PSDFonts.headline)

            if patterns.isEmpty {
                Text("Not enough data to identify patterns yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(patterns) { pattern in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: pattern.category.icon)
                            .foregroundStyle(pattern.category.color)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(pattern.techniqueName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(MarkdownParser.inline(pattern.insight))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if pattern.id != patterns.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Growth Pattern Model

struct GrowthPattern: Identifiable {
    let id = UUID()
    let techniqueName: String
    let category: PatternCategory
    let insight: String
}

enum PatternCategory {
    case consistentStrength
    case improving
    case needsAttention
    case changed

    var icon: String {
        switch self {
        case .consistentStrength: return "star.fill"
        case .improving: return "arrow.up.right"
        case .needsAttention: return "exclamationmark.triangle"
        case .changed: return "arrow.turn.down.right"
        }
    }

    var color: Color {
        switch self {
        case .consistentStrength: return PSDTheme.strength
        case .improving: return .blue
        case .needsAttention: return .orange
        case .changed: return .gray
        }
    }
}

// MARK: - Growth Pattern Analyzer

enum GrowthPatternAnalyzer {
    static func analyze(recordings: [Recording]) -> [GrowthPattern] {
        guard recordings.count >= 2 else { return [] }

        // Build technique rating histories
        var techniqueHistory: [String: (name: String, ratings: [Int])] = [:]

        for recording in recordings {
            guard let evaluations = recording.analysis?.techniqueEvaluations else { continue }
            for eval in evaluations {
                guard let rating = eval.rating else { continue }
                var entry = techniqueHistory[eval.techniqueId] ?? (name: eval.techniqueName, ratings: [])
                entry.ratings.append(rating)
                techniqueHistory[eval.techniqueId] = entry
            }
        }

        var patterns: [GrowthPattern] = []

        for (_, data) in techniqueHistory {
            let ratings = data.ratings
            guard ratings.count >= 2 else { continue }

            let first = ratings.first!
            let last = ratings.last!
            let avg = Double(ratings.reduce(0, +)) / Double(ratings.count)

            if ratings.allSatisfy({ $0 >= 4 }) {
                // Consistent strength
                patterns.append(GrowthPattern(
                    techniqueName: data.name,
                    category: .consistentStrength,
                    insight: "**\(data.name)** has been consistently strong (avg \(String(format: "%.1f", avg))). Keep it up."
                ))
            } else if last > first {
                // Improving
                patterns.append(GrowthPattern(
                    techniqueName: data.name,
                    category: .improving,
                    insight: "**\(data.name)** improved from \(first) to \(last) over \(ratings.count) sessions. This momentum is encouraging."
                ))
            } else if avg <= 2.5 {
                // Needs attention
                patterns.append(GrowthPattern(
                    techniqueName: data.name,
                    category: .needsAttention,
                    insight: "**\(data.name)** has been rated \(last) across \(ratings.count) sessions. Consider focusing your next coaching chat here."
                ))
            } else if last < first {
                // Changed (soft framing)
                patterns.append(GrowthPattern(
                    techniqueName: data.name,
                    category: .changed,
                    insight: "**\(data.name)** went from \(first) to \(last) over the last \(ratings.count) sessions \u{2014} worth revisiting."
                ))
            }
        }

        // Sort: needs attention first, then changed, then improving, then strengths
        let order: [PatternCategory] = [.needsAttention, .changed, .improving, .consistentStrength]
        patterns.sort { lhs, rhs in
            let lhsIndex = order.firstIndex(of: lhs.category) ?? 0
            let rhsIndex = order.firstIndex(of: rhs.category) ?? 0
            return lhsIndex < rhsIndex
        }

        return patterns
    }
}

// MARK: - Equatable for PatternCategory

extension PatternCategory: Equatable {}

#Preview {
    GrowthDashboardView()
        .environmentObject(AppState())
        .frame(width: 600, height: 800)
}
