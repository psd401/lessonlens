import SwiftUI
import SwiftData

/// List of coaching chat sessions for a recording
struct ChatListView: View {
    @Bindable var recording: Recording

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var sortedSessions: [ChatSession] {
        (recording.chatSessions ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedSessions.isEmpty {
                    emptyStateView
                } else {
                    sessionList
                }
            }
            .navigationTitle("Coaching Chats")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createNewSession()
                    } label: {
                        Label("New Chat", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 500, maxWidth: 700,
               minHeight: 380, idealHeight: 500, maxHeight: .infinity)
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            Button {
                createNewSession()
            } label: {
                Label("New Chat", systemImage: "plus.circle.fill")
                    .font(PSDFonts.headline)
                    .foregroundStyle(PSDTheme.accent)
            }
            .buttonStyle(.plain)

            ForEach(sortedSessions) { session in
                NavigationLink {
                    ChatPanelView(recording: recording, chatSession: session)
                } label: {
                    sessionRow(session)
                }
            }
            .onDelete(perform: deleteSessions)
        }
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(PSDFonts.headline)
                .lineLimit(1)

            HStack(spacing: 12) {
                let messageCount = session.sortedMessages.count
                Text("\(messageCount) message\(messageCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastMessage = session.sortedMessages.last {
                    Text(lastMessage.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No Coaching Chats")
                .font(.headline)

            Text("Start a new chat to ask follow-up questions about your lesson analysis.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                createNewSession()
            } label: {
                Label("New Chat", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(PSDTheme.accent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func createNewSession() {
        let session = ChatSession()
        modelContext.insert(session)
        session.recording = recording
        try? modelContext.save()
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sortedSessions[index]
            modelContext.delete(session)
        }
        try? modelContext.save()
    }
}
