import SwiftUI
import Fakthis

/// The short labels a brain-dump or chat answer named, if it named a Batch.
///
/// Classification, the same act as type inference: reading “that’s three tickets: …” into an
/// editable list. The labels are the words the PM used. Session does not parse the dump — the
/// window supplies them on `nameBatch`. Two or more, or nothing; a single name is not a Batch.
enum BatchNaming {
    static func shortLabels(in text: String) -> [String] {
        let cue =
            /(?i)(?:that'?s\s+)?(?:\d+|two|three|four|five|six|seven|eight|nine|ten)\s+tickets?\s*:\s*(.+)/
        guard let match = text.firstMatch(of: cue) else { return [] }
        let rest = String(match.1)
            .replacingOccurrences(of: #"\s+and\s+"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"\s*&\s*"#, with: ",", options: .regularExpression)
        return rest.split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".")))
            }
            .filter { !$0.isEmpty }
    }

    /// The list the form opens on. A Draft that already exists becomes Draft 1, so its short
    /// label leads; classified names from the field follow, and the form always has room for
    /// two because a Batch is at least that.
    static func labelsForForm(field: String, existingShortLabel: String?) -> [String] {
        var labels = shortLabels(in: field)
        if let existing = existingShortLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            labels.removeAll { $0.compare(existing, options: .caseInsensitive) == .orderedSame }
            labels.insert(existing, at: 0)
        }
        while labels.count < 2 { labels.append("") }
        return labels
    }
}

/// The control that does not go through the agent: a name and at least two short labels.
/// Before Generate it is the front-door toolbar (there is no rail yet). After a Draft exists it
/// is the same form, reached from chat classification or from the create rail.
struct NameBatchForm: View {
    var model: WindowModel
    var fromExistingDraft: Bool
    var cancel: (() -> Void)?

    @State private var name = ""
    @State private var labels: [LabelRow] = [LabelRow(), LabelRow()]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch")
                .font(.system(size: 15, weight: .semibold))
            Text(fromExistingDraft
                ? "The current Draft becomes Draft 1. Its Material, chat and answers stay."
                : "Name at least two Drafts. Generate writes each one; Submit writes the Batch.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 6) {
                ForEach($labels) { $row in
                    HStack(spacing: 6) {
                        Text("\((labels.firstIndex(where: { $0.id == row.id }) ?? 0) + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                        TextField("Short label", text: $row.text)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12.5))
                        if labels.count > 2 {
                            Button {
                                labels.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Add a Draft", systemImage: "plus") {
                    labels.append(LabelRow())
                }
                .buttonStyle(.accessoryBar)
            }

            HStack {
                if let cancel {
                    Button("Cancel", action: cancel)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button("Name Batch", action: confirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canConfirm || model.working)
            }
        }
        .padding(cancel == nil ? 0 : 18)
        .task {
            name = model.batch?.name ?? ""
            labels = BatchNaming.labelsForForm(
                field: model.field,
                existingShortLabel: fromExistingDraft ? model.draft?.shortLabel : nil
            ).map { LabelRow(text: $0) }
        }
    }

    private var trimmed: [String] {
        labels.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var canConfirm: Bool { trimmed.count >= 2 }

    private func confirm() {
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await model.perform(.nameBatch(name: named, shortLabels: trimmed))
            cancel?()
        }
    }
}

private struct LabelRow: Identifiable {
    let id = UUID()
    var text = ""
}

/// The sibling list as the rail. One control per sibling carries short label, Ticket type,
/// epic, position in the `blocks` chain and completeness; reordering happens on that control.
/// There is no separate chain strip and no gallery.
struct BatchRail: View {
    var model: WindowModel
    var batch: Batch

    @State private var adding = false
    @State private var newLabel = ""
    @State private var removing: BatchSibling?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnTitle("Batch") {
                HStack(spacing: 4) {
                    if !batch.blocks.isEmpty {
                        Button("No links") {
                            Task { await model.perform(.clearBlocks) }
                        }
                        .buttonStyle(.accessoryBar)
                        .disabled(model.working)
                    }
                    Button("Add", systemImage: "plus") { adding = true }
                        .buttonStyle(.accessoryBar)
                        .disabled(model.working)
                        .accessibilityLabel("Add a Draft")
                }
            }
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(batch.inChainOrder.enumerated()), id: \.element.id) { index, sibling in
                        SiblingControl(
                            model: model,
                            batch: batch,
                            sibling: sibling,
                            position: index + 1,
                            linking: !batch.blocks.isEmpty,
                            isLast: index == batch.inChainOrder.count - 1,
                            move: { move(sibling, by: $0) },
                            remove: { removing = sibling }
                        )
                    }
                }
            }
            media
        }
        .alert("Add a Draft", isPresented: $adding) {
            TextField("Short label", text: $newLabel)
            Button("Add") {
                let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                newLabel = ""
                guard !label.isEmpty else { return }
                Task { await model.perform(.addDraft(shortLabel: label)) }
            }
            Button("Cancel", role: .cancel) { newLabel = "" }
        } message: {
            Text("An empty Draft, appended. It needs its own Generate.")
        }
        .confirmationDialog(
            "Remove \(removing?.shortLabel ?? "this Draft")?",
            isPresented: Binding(
                get: { removing != nil },
                set: { if !$0 { removing = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let id = removing?.id else { return }
                removing = nil
                Task { await model.perform(.removeDraft(id)) }
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text(
                batch.siblings.count <= 2
                    ? "The Batch dissolves into the remaining Draft."
                    : "The Draft is deleted. There is no merge-back."
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(batch.name.isEmpty ? "Batch" : batch.name)
                    .font(.system(size: 12, weight: .medium))
                Text("\(batch.siblings.count) Drafts")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            epicPicker(label: "Default epic", selection: defaultEpic)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Text Material is already on every Generate; this is only the assignment screenshots
    /// and video need, because they default to the focused Draft.
    @ViewBuilder
    private var media: some View {
        let items = model.material
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                ColumnTitle("Material")
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.glyph)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.filename).font(.system(size: 11))
                            if item.isText {
                                Text("Visible to every Generate")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            } else if item.isMedia {
                                Menu("Also on") {
                                    ForEach(
                                        batch.siblings.filter { $0.id != batch.focusedDraftId },
                                        id: \.id
                                    ) { sibling in
                                        Button(sibling.shortLabel) {
                                            Task {
                                                await model.perform(
                                                    .assignMedia(
                                                        filename: item.filename,
                                                        draftIds: [batch.focusedDraftId, sibling.id]
                                                    )
                                                )
                                            }
                                        }
                                    }
                                }
                                .font(.system(size: 9.5))
                                .disabled(model.working)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var defaultEpic: Binding<TicketKey?> {
        Binding(
            get: { batch.defaultEpicKey },
            set: { key in
                Task { await model.perform(.setDefaultEpic(key)) }
            }
        )
    }

    private func epicPicker(label: String, selection: Binding<TicketKey?>) -> some View {
        Picker(label, selection: selection) {
            Text("None").tag(Optional<TicketKey>.none)
            ForEach(model.epics, id: \.key) { epic in
                Text(epic.name).tag(Optional(epic.key))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .disabled(model.working)
    }

    private func move(_ sibling: BatchSibling, by offset: Int) {
        var order = batch.inChainOrder.map(\.id)
        guard let index = order.firstIndex(of: sibling.id) else { return }
        let destination = index + offset
        guard order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        Task { await model.perform(.setBlocks(order)) }
    }
}

/// One sibling. Focus, identity, chain position and completeness live here so the list and the
/// `blocks` chain are not two controls the PM has to map onto each other.
private struct SiblingControl: View {
    var model: WindowModel
    var batch: Batch
    var sibling: BatchSibling
    var position: Int
    var linking: Bool
    var isLast: Bool
    var move: (Int) -> Void
    var remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            chain
            VStack(alignment: .leading, spacing: 4) {
                InPlaceEdit(
                    value: sibling.shortLabel,
                    commit: { await model.perform(.renameSibling(id: sibling.id, shortLabel: $0)) }
                ) { text in
                    TextField("Short label", text: text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .disabled(model.working)
                }
                HStack(spacing: 5) {
                    if let type = sibling.ticketType {
                        Text(type.label)
                            .font(.system(size: 9, weight: .semibold))
                            .textCase(.uppercase)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    epicMenu
                }
                completeness
            }
            Button(action: remove) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(model.working || sibling.key != nil)
            .accessibilityLabel("Remove \(sibling.shortLabel)")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            sibling.id == batch.focusedDraftId
                ? Color(nsColor: .windowBackgroundColor)
                : .clear
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(sibling.id == batch.focusedDraftId ? Color.accentColor : .clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await model.perform(.focusDraft(sibling.id)) }
        }
        .contextMenu {
            Button("Move up", action: { move(-1) })
                .disabled(position == 1 || model.working)
            Button("Move down", action: { move(1) })
                .disabled(isLast || model.working)
            Divider()
            Button("Remove…", role: .destructive, action: remove)
                .disabled(model.working || sibling.key != nil)
        }
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(sibling.id == batch.focusedDraftId ? .isSelected : [])
        .accessibilityAction(named: "Focus") {
            Task { await model.perform(.focusDraft(sibling.id)) }
        }
    }

    private var chain: some View {
        VStack(spacing: 1) {
            Button {
                move(-1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(position == 1 || model.working)
            .accessibilityLabel("Move up")
            Text("\(position)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            if linking && !isLast {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1, height: 10)
                Image(systemName: "arrow.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Button {
                move(1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(isLast || model.working)
            .accessibilityLabel("Move down")
        }
        .foregroundStyle(.tertiary)
        .frame(width: 16)
    }

    private var epicMenu: some View {
        let resolved = sibling.epicKey ?? batch.defaultEpicKey
        return Menu {
            Button("Default") {
                Task { await model.perform(.overrideEpic(id: sibling.id, nil)) }
            }
            ForEach(model.epics, id: \.key) { epic in
                Button(epic.name) {
                    Task { await model.perform(.overrideEpic(id: sibling.id, epic.key)) }
                }
            }
        } label: {
            Text(model.epicName(resolved) ?? "No epic")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .disabled(model.working)
    }

    private var completeness: some View {
        let ungenerated = sibling.ticketType == nil
        let open = !sibling.openQuestions.isEmpty
        return HStack(spacing: 4) {
            Circle()
                .fill(
                    ungenerated
                        ? Color(nsColor: .tertiaryLabelColor)
                        : (open ? Color.orange : Color(nsColor: .systemGreen))
                )
                .frame(width: 5, height: 5)
            Text(
                ungenerated
                    ? "needs Generate"
                    : (open ? "\(sibling.openQuestions.count) open" : "complete")
            )
            .font(.system(size: 9))
            .foregroundStyle(open && !ungenerated ? Color.orange : Color.secondary)
        }
    }

    private var accessibility: String {
        let type = sibling.ticketType?.label ?? "no Ticket type yet"
        let epic = model.epicName(sibling.epicKey ?? batch.defaultEpicKey) ?? "no epic"
        let complete = sibling.openQuestions.isEmpty
            ? "complete"
            : "\(sibling.openQuestions.count) open questions"
        return "\(sibling.shortLabel), \(type), \(epic), position \(position), \(complete)"
    }
}

/// Mid-chat conversion: the one-ticket description still holds Scope that now belongs to
/// siblings. Default on, never silent.
struct Draft1RegenerateOffer: View {
    var regenerate: () async -> Void
    var keep: () async -> Void
    var working: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Regenerate this description for Draft 1? Scope that belongs to siblings should not stay here.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Regenerate") { Task { await regenerate() } }
            Button("Keep") { Task { await keep() } }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(working)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }
}

/// One interrupt for the Batch, listing which Drafts hit which keys. Continue is always legal.
/// A Jira key offers work-on-that into Rewrite, which leaves the Batch.
struct BatchDuplicateInterrupt: View {
    var duplicates: [BatchDuplicate]
    var working: Bool
    var continueBatch: () async -> Void
    var workOn: (DuplicateHit) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fakthis")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.accentColor)
            Text("One of these Drafts looks like work that already exists.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(duplicates, id: \.draftId) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(item.shortLabel) looks like \(item.hit.looksLike).")
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if item.hit.key != nil {
                        Button("Work on \(item.hit.looksLike)") {
                            Task { await workOn(item.hit) }
                        }
                        .disabled(working)
                    }
                }
            }
            Button("Continue") { Task { await continueBatch() } }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.orange.opacity(0.45))
        }
        .accessibilityElement(children: .contain)
    }
}
