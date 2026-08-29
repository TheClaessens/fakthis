import SwiftUI

/// The Draft's description on screen. The agent writes Markdown in a deliberately small
/// vocabulary — paragraphs, bold, bullets, ordered lists, links, one horizontal rule, no
/// headings (§8) — so this renders that vocabulary and nothing more.
///
/// It reads the description; it does not decide what is in it. Where the open-questions section
/// sits is `Draft`'s business, and the string arrives with it already in place.
struct MarkdownBlocks: View {
    var markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .rule:
                    Divider().padding(.vertical, 2)
                case .paragraph(let text):
                    inline(text)
                        .fixedSize(horizontal: false, vertical: true)
                case .list(let items, let ordered):
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(ordered ? "\(index + 1)." : "•")
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                                inline(item)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    private func inline(_ text: String) -> Text {
        guard
            let attributed = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        else { return Text(text) }
        return Text(attributed)
    }

    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(markdown) }
}

enum MarkdownBlock {
    case paragraph(String)
    case list([String], ordered: Bool)
    case rule

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var list: (items: [String], ordered: Bool)?

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
            if let list {
                blocks.append(.list(list.items, ordered: list.ordered))
            }
            list = nil
        }

        func append(_ item: String, ordered: Bool) {
            if list?.ordered != ordered { flush() }
            list = (items: (list?.items ?? []) + [item], ordered: ordered)
        }

        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line == "---" {
                flush()
                blocks.append(.rule)
            } else if line.hasPrefix("- ") {
                append(String(line.dropFirst(2)), ordered: false)
            } else if let numbered = numberedItem(line) {
                append(numbered, ordered: true)
            } else {
                if list != nil { flush() }
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func numberedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}
