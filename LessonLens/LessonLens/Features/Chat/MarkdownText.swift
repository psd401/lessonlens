import SwiftUI

/// A block of lightweight Markdown, parsed line by line.
/// Inline syntax (bold, italics, code, links) stays in `text` and is rendered by `AttributedString`.
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(String)
    case bullet(String, indent: Int)
    case numbered(String, number: Int, indent: Int)
}

enum MarkdownParser {
    /// Splits text into paragraphs, headings, and bullet/numbered list items.
    /// Unrecognized syntax is kept as paragraph text so nothing is dropped.
    static func blocks(from text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let indent = min(leadingSpaces(rawLine) / 2, 3)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Horizontal rules (---, ***, ___) add nothing in a chat bubble
            if trimmed.count >= 3, Set(trimmed).count == 1, "-*_".contains(trimmed.first!) {
                flushParagraph()
                continue
            }

            let digits = trimmed.prefix { $0.isASCII && $0.isNumber }

            if let heading = content(after: trimmed.prefix { $0 == "#" }, in: trimmed, maxMarker: 6) {
                flushParagraph()
                blocks.append(.heading(heading))
            } else if let first = trimmed.first, "*-+".contains(first),
                      let item = content(after: trimmed.prefix(1), in: trimmed, maxMarker: 1) {
                flushParagraph()
                blocks.append(.bullet(item, indent: indent))
            } else if !digits.isEmpty,
                      let delimiter = trimmed.dropFirst(digits.count).first, delimiter == "." || delimiter == ")",
                      let item = content(after: trimmed.prefix(digits.count + 1), in: trimmed, maxMarker: 4) {
                flushParagraph()
                blocks.append(.numbered(item, number: Int(digits) ?? 1, indent: indent))
            } else if paragraph.isEmpty, indent > 0, let last = blocks.last, let continued = appending(trimmed, to: last) {
                // Indented line directly under a list item continues that item
                blocks[blocks.count - 1] = continued
            } else {
                paragraph.append(trimmed)
            }
        }
        flushParagraph()
        return blocks
    }

    /// Parses inline Markdown; falls back to the literal text if parsing fails.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// Returns the text after a line marker (e.g. "#", "*", "1.") when the marker is followed by whitespace.
    private static func content(after marker: Substring, in line: String, maxMarker: Int) -> String? {
        guard !marker.isEmpty, marker.count <= maxMarker else { return nil }
        let rest = line.dropFirst(marker.count)
        guard let next = rest.first, next.isWhitespace else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func appending(_ line: String, to block: MarkdownBlock) -> MarkdownBlock? {
        switch block {
        case .bullet(let text, let indent):
            return .bullet(text + " " + line, indent: indent)
        case .numbered(let text, let number, let indent):
            return .numbered(text + " " + line, number: number, indent: indent)
        default:
            return nil
        }
    }
}

/// Renders basic Markdown (bold, italics, bullet and numbered lists, paragraphs) for chat replies
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownParser.blocks(from: text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(MarkdownParser.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let text):
            Text(MarkdownParser.inline(text))
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text, let indent):
            listItem(marker: "•", text: text, indent: indent)
        case .numbered(let text, let number, let indent):
            listItem(marker: "\(number).", text: text, indent: indent)
        }
    }

    private func listItem(marker: String, text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .monospacedDigit()
            Text(MarkdownParser.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(indent) * 16)
    }
}
