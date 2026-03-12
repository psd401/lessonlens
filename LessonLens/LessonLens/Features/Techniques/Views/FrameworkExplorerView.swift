import SwiftUI

/// Browse all teaching frameworks and their techniques
struct FrameworkExplorerView: View {
    @State private var selectedFramework: TeachingFramework = .psdEssentials

    static var sortedFrameworks: [TeachingFramework] {
        TeachingFramework.allCases.sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(Self.sortedFrameworks, selection: $selectedFramework) { framework in
                VStack(alignment: .leading, spacing: 4) {
                    Text(framework.shortName)
                        .font(PSDFonts.headline)
                    Text(framework.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(framework)
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            FrameworkDetailView(framework: selectedFramework)
        }
    }
}

// MARK: - Framework Detail View

struct FrameworkDetailView: View {
    let framework: TeachingFramework

    private var groupedTechniques: [(category: TechniqueCategory, techniques: [Technique])] {
        FrameworkRegistry.techniquesByCategory(for: framework)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(framework.displayName)
                        .font(PSDFonts.largeTitle)

                    Text(framework.description)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if let url = framework.learnMoreURL {
                        Link(destination: url) {
                            Label("Learn More", systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                    }
                }

                // Techniques grouped by category
                ForEach(groupedTechniques, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Label(group.category.rawValue, systemImage: group.category.icon)
                            .font(PSDFonts.headline)
                            .foregroundStyle(PSDTheme.accent)

                        ForEach(group.techniques) { technique in
                            TechniqueDetailCard(technique: technique)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .psdPageBackground()
    }
}

// MARK: - Technique Detail Card

struct TechniqueDetailCard: View {
    let technique: Technique
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(technique.name)
                        .font(.headline)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Text(technique.descriptionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Look Fors
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Look Fors")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(technique.lookFors, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "eye")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item)
                                    .font(.callout)
                            }
                        }
                    }

                    // Exemplar Phrases
                    if !technique.exemplarPhrases.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Exemplar Phrases")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            ForEach(technique.exemplarPhrases, id: \.self) { phrase in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\u{201C}")
                                        .foregroundStyle(.secondary)
                                    Text(phrase)
                                        .font(.callout)
                                        .italic()
                                    Text("\u{201D}")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .psdCard()
    }
}

#Preview {
    FrameworkExplorerView()
}
