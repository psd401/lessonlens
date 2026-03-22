import SwiftUI

/// Reusable view for selecting a teaching framework with technique disclosure
struct FrameworkSelectionView: View {
    @Binding var selectedFramework: TeachingFramework
    @Binding var enabledTechniqueIds: Set<String>

    @Environment(\.serviceContainer) private var services

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Framework Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Teaching Framework")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Framework", selection: $selectedFramework) {
                    ForEach(TeachingFramework.allCases) { framework in
                        Text(framework.displayName).tag(framework)
                    }
                }
                .pickerStyle(.menu)

                Text(selectedFramework.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Technique Disclosure
            DisclosureGroup(isExpanded: $isExpanded) {
                TechniqueChecklistView(
                    framework: selectedFramework,
                    enabledTechniqueIds: $enabledTechniqueIds
                )
            } label: {
                HStack {
                    Text("Techniques")
                        .font(.subheadline)

                    Spacer()

                    Text("\(enabledTechniqueIds.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Tip: Selecting 3\u{2013}5 techniques provides more focused, actionable feedback")
                    .font(.caption)
                    .foregroundStyle(enabledTechniqueIds.count > 8 ? .orange : .secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var framework: TeachingFramework = .tlac
        @State var enabledIds: Set<String> = Set(TLACTechniques.defaultEnabledIds)

        var body: some View {
            FrameworkSelectionView(
                selectedFramework: $framework,
                enabledTechniqueIds: $enabledIds
            )
            .padding()
            .frame(width: 400)
        }
    }

    return PreviewWrapper()
}
