import SwiftUI
import Fakthis

/// What Generate reveals: one window, three columns — rail, Draft, conversation. Create, Batch
/// and Rewrite are not modes of it; they are what the rail holds, which is why the Draft and the
/// conversation keep their shape across all three and the Draft is designed once.
struct Workbench: View {
    var model: WindowModel
    var draft: Draft

    /// Whether the conversation is a spine. The surface owns it rather than the column, because
    /// Rewrite has to be able to open with it already collapsed — Update does not require
    /// Generate — and Rewrite is its own ticket. Create opens with it open.
    @State private var conversationCollapsed = false

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
                if !model.draftSignals.isEmpty {
                    SignalGutter(signals: model.draftSignals, open: $signalsOpen)
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

    /// Fixed, so Submit is on screen whatever the description does above it. After Submit the
    /// same strip names the Ticket and carries the upload step.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let submitted = model.submitted {
                submittedRow(submitted)
                uploadStep(key: submitted.key)
            } else {
                submitRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
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
