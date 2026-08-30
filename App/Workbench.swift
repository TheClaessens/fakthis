import SwiftUI
import Fakthis

/// What Generate reveals: one window, three columns — rail, Draft, conversation. Create, Batch
/// and Rewrite are not modes of it; they are what the rail holds, which is why the Draft and the
/// conversation keep their shape across all three and the Draft is designed once.
struct Workbench: View {
    var model: WindowModel
    var draft: Draft

    /// Whether the conversation is a spine. The surface owns it rather than the column, because
    /// Rewrite opens with it already collapsed — Update does not require Generate — and a
    /// keyboard-only rewrite should not stare at an empty third of the window. Create and Batch
    /// open it for chat.
    @State private var conversationCollapsed: Bool
    /// The control that names a Batch after a Draft exists. Before Generate that control is a
    /// toolbar button on the front door; here it hangs off Material, because there is a rail.
    @State private var namingBatch = false

    init(model: WindowModel, draft: Draft) {
        self.model = model
        self.draft = draft
        _conversationCollapsed = State(initialValue: model.rewrite != nil)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail.frame(width: 262)
            Divider()
            DraftColumn(model: model, draft: draft)
                .frame(minWidth: 460, maxWidth: .infinity)
            Divider()
            ConversationColumn(model: model, collapsed: $conversationCollapsed)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.duplicateInterrupt) { _, hit in
            // The interrupt is a conversation event at the moment it fires. A collapsed spine
            // would hide it, and Continue cannot be pressed from a mark that does not exist yet.
            if hit != nil { conversationCollapsed = false }
        }
        .onChange(of: model.batchDuplicates.isEmpty) { _, empty in
            if !empty { conversationCollapsed = false }
        }
        .onChange(of: model.rewrite != nil) { _, rewriting in
            // Duplicate → work-on-that lands in Rewrite on this same Workbench. Init does not
            // run again, so the collapse has to happen here. Update clearing `rewrite` must
            // not expand the spine — the PM did not ask for a conversation.
            if rewriting { conversationCollapsed = true }
        }
    }

    // MARK: - Rail

    /// Create: Material, and Related when there are hits. Batch: the sibling list. Rewrite: the
    /// live description and comments, beside the Draft. Related stays under any of them — it is
    /// Context for the next turn, not a second rail.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let rewrite = model.rewrite {
                RewriteRail(rewrite: rewrite)
                related
            } else if let batch = model.batch {
                BatchRail(model: model, batch: batch)
                related
            } else {
                material
                related
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var material: some View {
        VStack(alignment: .leading, spacing: 0) {
            if namingBatch {
                NameBatchForm(
                    model: model,
                    fromExistingDraft: true,
                    cancel: { namingBatch = false }
                )
            } else {
            ColumnTitle("Material") {
                if model.editable && model.rewrite == nil {
                    Button("Batch", systemImage: "list.bullet.rectangle") {
                        namingBatch = true
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(model.working)
                    .accessibilityLabel("Name a Batch")
                }
            }
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
            }
        }
    }

    /// Ignorable, default off as a write. Ticking a key is Context for the next turn; nothing
    /// is injected into the description and no Jira issue links are written. Session caps at
    /// three and sends the ticks; the window only draws what is there.
    @ViewBuilder
    private var related: some View {
        if !model.related.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ColumnTitle("Related")
                ForEach(model.related, id: \.key) { hit in
                    Button {
                        Task { await model.perform(.tickRelated(hit.key)) }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: hit.ticked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    hit.ticked
                                        ? Color.accentColor
                                        : Color(nsColor: .tertiaryLabelColor)
                                )
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(hit.key.value)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(hit.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.editable || model.working)
                    .accessibilityLabel(
                        hit.ticked
                            ? "\(hit.key.value), ticked as Context"
                            : "\(hit.key.value), \(hit.title)"
                    )
                }
            }
        }
    }
}

/// The Draft column is **bounded with a fixed footer**. It is the constraint that chose the
/// window's shape: Submit and the rewrite diff have to be reachable at any window height and any
/// description length, so the Draft scrolls inside the column and the footer does not move.
///
/// The column is the editor until Submit and the upload queue after it. §4: once the Jira issue
/// exists the folder is a queue plus the key, never an editor again — so the fields stop taking
/// edits and the footer stops offering Submit and starts naming the Ticket.
struct DraftColumn: View {
    var model: WindowModel
    var draft: Draft

    /// The gutter is the resting state and what the window opens with. The panel is temporary,
    /// and costs the Draft width while it is up (`Prototype/FINDINGS.md` 16), so it closes again
    /// the moment there is nothing left to rest in the gutter.
    @State private var signalsOpen = false

    var body: some View {
        VStack(spacing: 0) {
            ColumnTitle("Draft")
            // The panel and the gutter are siblings of the scroll, not layers over it: whatever
            // they take, they take out of the Draft's width, and nothing about the Draft is
            // covered. The footer spans beneath them, so Submit stays reachable either way.
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        identity
                        title
                        FieldWarnings(warnings: model.titleWarnings)
                        Divider()
                        if model.offerRegenerateDraft1 {
                            Draft1RegenerateOffer(
                                regenerate: { await model.generate() },
                                keep: { await model.perform(.dismissRegenerateOffer) },
                                working: model.working
                            )
                        }
                        if model.offerRegenerateDefinitionOfDone {
                            DefinitionOfDoneOffer(
                                regenerate: { await model.regenerateDefinitionOfDone() },
                                keep: { await model.perform(.keepDefinitionOfDone) },
                                working: model.working
                            )
                        }
                        DescriptionEditor(
                            draft: draft,
                            editable: model.editable && !model.working,
                            commit: { await model.perform(.editDescription($0)) },
                            finish: { await model.perform(.finishEditingDescription) }
                        )
                        FieldWarnings(warnings: model.descriptionWarnings)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                if signalsOpen {
                    SignalPanel(
                        signals: model.draftSignals,
                        working: model.working,
                        retryUploads: { await model.retryUploads() },
                        skipUploads: { await model.perform(.skipFailedUploads) },
                        open: $signalsOpen
                    )
                }
                if !model.draftSignals.isEmpty || model.duplicateMark != nil {
                    SignalGutter(
                        signals: model.draftSignals,
                        duplicateMark: model.duplicateMark,
                        open: $signalsOpen
                    )
                }
            }
            .onChange(of: model.draftSignals) { _, signals in
                if signals.isEmpty { signalsOpen = false }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            if model.working {
                ProgressView().controlSize(.large)
            }
        }
    }

    /// Ticket type renders inline with the short label. They are the two things checked first,
    /// and a Story title beginning "As a" is useless for either job. Changing the type reshapes
    /// the Draft against the new template and keeps Material and the answers already given —
    /// which is `Session`'s rule, not something this control repeats.
    private var identity: some View {
        HStack(spacing: 8) {
            if model.editable {
                Picker("Ticket type", selection: ticketType) {
                    ForEach(TicketType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .disabled(model.working)
            } else {
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
            }

            InPlaceEdit(
                value: draft.shortLabel,
                commit: { await model.perform(.editShortLabel($0)) }
            ) { text in
                TextField("Short label", text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .disabled(!model.editable || model.working)
            }
        }
    }

    private var ticketType: Binding<TicketType> {
        Binding(
            get: { draft.ticketType },
            set: { type in
                guard type != draft.ticketType else { return }
                Task { await model.changeTicketType(type) }
            }
        )
    }

    private var title: some View {
        InPlaceEdit(value: draft.title, commit: { await model.perform(.editTitle($0)) }) { text in
            TextField("Title", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
                .disabled(!model.editable || model.working)
        }
    }

    // MARK: - Footer

    /// Fixed, so Submit and the rewrite diff are on screen whatever the description does above
    /// them. After the write the same strip names the Ticket and carries the upload step.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let submitted = model.submitted, model.batch == nil {
                submittedRow(submitted)
                uploadStep(key: submitted.key)
            } else if let rewrite = model.rewrite, let key = draft.key {
                RewriteFooter(model: model, draft: draft, rewrite: rewrite, key: key)
            } else if let batch = model.batch {
                batchSubmitRow(batch)
            } else {
                submitRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// One Submit for the Batch. It sits on the Batch, not on the focused Draft — focusing
    /// another sibling does not produce a second button, and a sibling that already has a key
    /// does not replace it with New Draft.
    private func batchSubmitRow(_ batch: Batch) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Submit writes all \(batch.siblings.count) in \(model.projectKey)"
                    + (batch.blocks.isEmpty ? "." : ", blocker first."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                if model.submitRefused {
                    Text("Jira did not answer. Already-created siblings stay — Submit again.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button {
                Task { await model.submit() }
            } label: {
                Label("Submit", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.working)
        }
    }

    private var submitRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Draft in \(model.projectKey)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                if model.submitRefused {
                    Text("Jira did not answer. The Draft is unchanged — Submit again.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button {
                Task { await model.submit() }
            } label: {
                Label("Submit", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.working)
        }
    }

    /// The key and the link, first: the Jira issue exists, and nothing below this line can put it
    /// at risk. New Draft waits for the queue to empty, because the queue is the one thing here
    /// that is not also in Jira.
    private func submittedRow(_ submitted: SubmittedTicket) -> some View {
        HStack(spacing: 10) {
            if let url = submitted.url {
                Link(destination: url) {
                    Label(submitted.key.value, systemImage: "arrow.up.right.square")
                }
                .font(.system(size: 13, weight: .semibold))
            } else {
                Text(submitted.key.value).font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            if model.canStartANewDraft {
                Button("New Draft", systemImage: "plus") {
                    Task { await model.perform(.newDraft) }
                }
                .buttonStyle(.bordered)
                .disabled(model.working)
            }
        }
    }

    /// Media upload is its own step, after the Ticket exists. What went wrong with it — a file
    /// Jira would not take, a file that did not upload — is a **Draft signal** and rests in the
    /// gutter with the other two, so it is never on screen in two places at once. What is left
    /// here is the one thing the gutter has no mark for: the queue is empty and the media is on
    /// the Ticket.
    @ViewBuilder
    private func uploadStep(key: TicketKey) -> some View {
        if !model.media.isEmpty && model.failedUploads.isEmpty {
            Label("Media uploaded to \(key.value).", systemImage: "checkmark.circle")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }
}

struct ColumnTitle<Accessory: View>: View {
    var text: String
    @ViewBuilder var accessory: () -> Accessory

    init(_ text: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.text = text
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(text)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                accessory()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            // Fixed, so a title carrying a control still lines up across the three columns.
            .frame(height: 33)
            Divider()
        }
    }
}

extension ColumnTitle where Accessory == EmptyView {
    init(_ text: String) {
        self.init(text) { EmptyView() }
    }
}

/// The Ticket type's own name. It belongs in the library, but the throwaway prototype target
/// already declares one; it moves there when #40 retires it.
extension TicketType {
    var label: String {
        switch self {
        case .story: "Story"
        case .bug: "Bug"
        case .chore: "Chore"
        }
    }
}
