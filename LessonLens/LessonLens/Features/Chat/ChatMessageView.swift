import SwiftUI

/// Bubble-style message view for chat
struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Group {
                    if message.isAssistant {
                        MarkdownText(text: message.content)
                    } else {
                        Text(message.content)
                    }
                }
                .font(.body)
                .foregroundStyle(message.isUser ? .white : .primary)
                .textSelection(.enabled)

                Text(message.createdAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(message.isUser ? .white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.isUser ? AnyShapeStyle(PSDTheme.accent) : AnyShapeStyle(.regularMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if message.isAssistant { Spacer(minLength: 60) }
        }
    }
}
