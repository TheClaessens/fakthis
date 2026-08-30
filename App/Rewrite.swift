import SwiftUI
import Fakthis

/// The landing before a rewrite Draft exists: a key field, not a browser. It replaces the
/// front-door composer until the fetch returns a Draft, because there is still no rail to hang
/// a key field on.
///
/// Epic keys, other-project keys and a 404 are `Session`'s refusals — the window prints what
/// `rewriteError` already says. An unreachable Jira is the same shape as a refused Project key:
/// the press did nothing, so the window says so.
struct ImproveExisting: View {
    var model: WindowModel
    var cancel: () -> Void

    @State private var key = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Improve existing")
                .font(.system(size: 15, weight: .semibold))
            Text("Paste a Ticket key.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            TextField("\(model.projectKey)-000", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .focused($typing)
                .onSubmit(fetch)
                .disabled(model.working)
                .accessibilityLabel("Ticket key")

            if let error = model.rewriteError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.pasteKeyRefused {
                Text("Jira did not answer for that key. Nothing was fetched — try again.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Fetch", action: fetch)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.working || trimmed.isEmpty)
            }
        }
        .padding(18)
        .task { typing = true }
        .overlay {
            if model.working {
                ProgressView().controlSize(.large)
            }
        }
    }

    private var trimmed: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetch() {
        let entered = trimmed.uppercased()
        guard !entered.isEmpty else { return }
        Task { await model.pasteKey(entered) }
    }
}

/// What the rail holds on Rewrite: the live description and comments, beside the Draft and
/// readable. Above is not next to — above would push the Draft down and still lose the diff.
struct RewriteRail: View {
    var rewrite: Rewrite

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnTitle("Improve existing")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    liveBody
                    Divider()
                    comments
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var liveBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live description")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(rewrite.liveDescription.isEmpty ? "No description." : rewrite.liveDescription)
                .font(.system(size: 11))
                .foregroundStyle(rewrite.liveDescription.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(commentsHeading)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if rewrite.comments.isEmpty {
                Text("No comments.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(rewrite.comments.enumerated()), id: \.offset) { _, comment in
                    Text(comment)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 7)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor))
                                .frame(width: 2)
                        }
                }
            }
            if rewrite.commentsTruncated {
                Text("Showing the 50 newest. Older comments are not here.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var commentsHeading: String {
        switch rewrite.comments.count {
        case 0: "Comments"
        case 1: "Comments · 1, newest first"
        default: "Comments · \(rewrite.comments.count), newest first"
        }
    }
}

/// The rewrite half of the Draft's fixed footer: the diff, then `Update <KEY>`. Both stay on
/// screen at any window height because they live in the footer, not in the description scroll.
struct RewriteFooter: View {
    var model: WindowModel
    var draft: Draft
    var rewrite: Rewrite
    var key: TicketKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RewriteDiff(
                before: rewrite.liveDescription,
                after: draft.descriptionWithOpenQuestions,
                key: key
            )
            if rewrite.stale {
                Text(
                    "Jira changed since this fetch. Re-fetch keeps the Draft and refreshes Material."
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            updateRow
        }
    }

    /// Re-fetch is the default when Jira moved: prominent, first. The write is still
    /// `Update <KEY>` with the watchers note — those two facts do not leave the footer
    /// because a stale `updated` is a warn, not a different button.
    private var updateRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rewrite.watchersNote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                if model.updateRefused {
                    Text("Jira did not answer. The Draft is unchanged — Update again.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if rewrite.stale {
                Button("Re-fetch") {
                    Task { await model.refetch() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.working)
                Button {
                    Task { await model.clobber() }
                } label: {
                    Label("Update \(key.value)", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.working)
            } else {
                Button {
                    Task { await model.update() }
                } label: {
                    Label("Update \(key.value)", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.working)
            }
        }
    }
}

/// Line-by-line against the fetched live body. It sits in the footer so a long description
/// cannot push it off the screen — that is the constraint that chose the window shape.
struct RewriteDiff: View {
    var before: String
    var after: String
    var key: TicketKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Diff against live \(key.value)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(glyph(line.kind))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(colour(line.kind))
                                .frame(width: 9)
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(line.kind == .same ? .tertiary : .primary)
                                .strikethrough(line.kind == .cut, color: Color.red.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(fill(line.kind))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor))
            }
        }
    }

    private var lines: [DiffLine] { diffLines(from: before, to: after) }

    private func glyph(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .same: " "
        case .cut: "−"
        case .add: "+"
        }
    }

    private func colour(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .same: Color(nsColor: .tertiaryLabelColor)
        case .cut: Color(nsColor: .systemRed)
        case .add: Color(nsColor: .systemGreen)
        }
    }

    private func fill(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .same: .clear
        case .cut: Color(nsColor: .systemRed).opacity(0.10)
        case .add: Color(nsColor: .systemGreen).opacity(0.10)
        }
    }
}

private struct DiffLine {
    enum Kind { case same, cut, add }
    var kind: Kind
    var text: String
}

/// Line LCS. What "wholesale replace is not silent" (§12) needs and nothing more: the lines the
/// Update drops, and the lines it writes.
private func diffLines(from before: String, to after: String) -> [DiffLine] {
    let a = before.components(separatedBy: "\n")
    let b = after.components(separatedBy: "\n")
    var table = Array(
        repeating: Array(repeating: 0, count: b.count + 1),
        count: a.count + 1
    )
    for i in stride(from: a.count - 1, through: 0, by: -1) {
        for j in stride(from: b.count - 1, through: 0, by: -1) {
            table[i][j] = a[i] == b[j]
                ? table[i + 1][j + 1] + 1
                : max(table[i + 1][j], table[i][j + 1])
        }
    }
    var out: [DiffLine] = []
    var i = 0, j = 0
    while i < a.count && j < b.count {
        if a[i] == b[j] {
            out.append(DiffLine(kind: .same, text: a[i]))
            i += 1
            j += 1
        } else if table[i + 1][j] >= table[i][j + 1] {
            out.append(DiffLine(kind: .cut, text: a[i]))
            i += 1
        } else {
            out.append(DiffLine(kind: .add, text: b[j]))
            j += 1
        }
    }
    while i < a.count {
        out.append(DiffLine(kind: .cut, text: a[i]))
        i += 1
    }
    while j < b.count {
        out.append(DiffLine(kind: .add, text: b[j]))
        j += 1
    }
    return out.filter { !($0.kind == .same && $0.text.isEmpty) }
}
