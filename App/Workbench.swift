import SwiftUI
import Fakthis

/// What Generate reveals: one window, three columns — rail, Draft, conversation. Create, Batch
/// and Rewrite are not modes of it; they are what the rail holds, which is why the Draft and the
/// conversation keep their shape across all three and the Draft is designed once.
struct Workbench: View {
    var model: WindowModel
    var draft: Draft

    var body: some View {
        HStack(spacing: 0) {
            rail.frame(width: 262)
            Divider()
            DraftColumn(model: model, draft: draft)
                .frame(minWidth: 460, maxWidth: .infinity)
            Divider()
            conversation.frame(width: 316)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Rail

    /// On Create the rail holds Material. Related, the sibling list and the live body are what it
    /// holds on the other surfaces; those are their own tickets.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnTitle("Material")
            if model.material.isEmpty {
                Text("Nothing attached.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.material.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.glyph)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(width: 14)
                            Text(item.filename).font(.system(size: 11))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Conversation

    /// The column exists from the moment the Draft does, because it is where the agent's turns
    /// and the PM's answers go. It has nothing to render yet: `Session` persists a transcript
    /// but does not expose one, which is #30's gap and not something the window may invent.
    private var conversation: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnTitle("Conversation")
            Spacer()
            Text("Nothing said yet.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// The Draft column is **bounded with a fixed footer**. It is the constraint that chose the
/// window's shape: Submit and the rewrite diff have to be reachable at any window height and any
/// description length, so the description scrolls inside the column and the footer does not move.
/// Later tickets hang Submit, the diff and the gutter off this structure.
struct DraftColumn: View {
    var model: WindowModel
    var draft: Draft

    var body: some View {
        VStack(spacing: 0) {
            ColumnTitle("Draft")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identity
                    Text(draft.title)
                        .font(.system(size: 18, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    MarkdownBlocks(markdown: draft.descriptionWithOpenQuestions)
                        .font(.system(size: 12.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Ticket type renders inline with the short label. They are the two things checked first,
    /// and a Story title beginning "As a" is useless for either job.
    private var identity: some View {
        HStack(spacing: 8) {
            Text(draft.ticketType.label)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
            Text(draft.shortLabel)
                .font(.system(size: 12.5, weight: .medium))
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Text(draft.key?.value ?? "Draft in \(model.projectKey)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ColumnTitle: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(text)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            Divider()
        }
    }
}

/// The Ticket type's own name, fixed by `CONTEXT.md`. It belongs in the library, but the
/// throwaway prototype target already declares one; it moves there when #40 retires it.
extension TicketType {
    var label: String {
        switch self {
        case .story: "Story"
        case .bug: "Bug"
        case .chore: "Chore"
        }
    }
}
