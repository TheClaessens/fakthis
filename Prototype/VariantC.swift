// THROWAWAY PROTOTYPE — Variant C, "Rail", second pass.
//
// ONE window, one layout, three columns: a contextual rail, the Draft, the conversation.
// Create / Batch / Rewrite are what the left rail holds, not modes of the window.
//
// Second pass fixes the three things the first pass got wrong:
//   1. The signal panel now DISPLACES the Draft column instead of floating over it.
//   2. The conversation column COLLAPSES to a spine, and Rewrite opens collapsed.
//   3. The pre-Generate state is designed rather than being an empty Draft skeleton — and
//      because there is no obvious right answer, it comes in three styles.
//
// After Generate all three styles are the same window. They differ only in the state that had
// no design at all in the first pass.

import SwiftUI
import Fakthis

enum PreGenerate: String, CaseIterable {
    /// Three columns throughout. The field is promoted into the Draft column until a Draft
    /// exists, then demotes to the composer on the right.
    case fieldCentre
    /// Two columns until Generate. The conversation column does not exist before there is a
    /// conversation; the window gains it when the Draft appears.
    case twoColumn
    /// No columns until Generate. A front door: one field on the canvas, Material dropped onto
    /// it, and the workbench materialises on Generate.
    case frontDoor

    var label: String {
        switch self {
        case .fieldCentre: "field takes the centre"
        case .twoColumn: "two columns until Generate"
        case .frontDoor: "front door, then the workbench"
        }
    }
}

struct VariantC: View {
    @Bindable var store: Store
    var style: PreGenerate = .fieldCentre
    @State private var signalsExpanded = true

    var body: some View {
        if store.hasDraft {
            workbench
        } else {
            switch style {
            case .fieldCentre: fieldCentreWindow
            case .twoColumn: twoColumnWindow
            case .frontDoor: frontDoorWindow
            }
        }
    }

    // MARK: - The workbench (identical on all three styles, once a Draft exists)

    private var workbench: some View {
        HStack(spacing: 0) {
            surfacePicker
            VRule()
            rail.frame(width: 262)
            VRule()
            draftColumn
            if signalsExpanded && !store.signals.isEmpty {
                VRule()
                signalPanel.frame(width: 288)
            }
            VRule()
            conversationColumn
        }
        .background(Ink.canvas)
    }

    // MARK: - Pre-Generate, style 1: the field takes the Draft column

    private var fieldCentreWindow: some View {
        HStack(spacing: 0) {
            surfacePicker
            VRule()
            materialRail.frame(width: 262)
            VRule()
            VStack(spacing: 0) {
                PaneTitle("Brain-dump") {
                    HStack(spacing: 9) {
                        Text(store.epicName).font(.system(size: 10.5)).foregroundStyle(Ink.dim)
                        TypeControl(selection: store.ticketType, compact: true)
                    }
                }
                VStack(alignment: .leading, spacing: 11) {
                    Text("Say or type what the work is. The agent writes the Ticket.")
                        .font(.system(size: 11.5)).foregroundStyle(Ink.faint)
                    BodyField(text: $store.field, font: .system(size: 14))
                        .frame(maxHeight: .infinity)
                }
                .padding(16)
                HRule()
                preGenerateFooter
            }
            .background(Ink.panel)
            VRule()
            collapsedConversation(note: "Nothing said yet")
        }
        .background(Ink.canvas)
    }

    // MARK: - Pre-Generate, style 2: two columns until Generate

    private var twoColumnWindow: some View {
        HStack(spacing: 0) {
            surfacePicker
            VRule()
            materialRail.frame(width: 262)
            VRule()
            VStack(spacing: 0) {
                VoiceStrip(
                    phase: store.voice,
                    gesture: "⌥ to start / stop",
                    compileInProgress: store.aneCompileInProgress
                )
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        Text("New Ticket in \(store.epicName)")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.ink)
                        Spacer()
                        TypeControl(selection: store.ticketType, compact: true)
                    }
                    BodyField(text: $store.field, font: .system(size: 14))
                        .frame(maxHeight: .infinity)
                    Text("Generate is a separate press. Nothing reaches the agent until you "
                        + "press it.")
                        .font(.system(size: 10.5)).foregroundStyle(Ink.faint)
                }
                .padding(18)
                HRule()
                preGenerateFooter
            }
            .background(Ink.panel)
        }
        .background(Ink.canvas)
    }

    // MARK: - Pre-Generate, style 3: a front door

    private var frontDoorWindow: some View {
        ZStack {
            Ink.canvas
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 12)).foregroundStyle(Ink.accent)
                    Text("FAK").font(.system(size: 12.5, weight: .semibold))
                    Text(store.epicName).font(.system(size: 11)).foregroundStyle(Ink.dim)
                    Spacer()
                    Press(title: "Batch", glyph: "list.bullet.rectangle", kind: .quiet)
                    Press(title: "Improve existing", glyph: "arrow.triangle.2.circlepath",
                          kind: .quiet)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Ink.panel)
                HRule()
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    VoiceStrip(
                        phase: store.voice,
                        gesture: "⌥ to start / stop",
                        compileInProgress: store.aneCompileInProgress
                    )
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("What is the work?")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Ink.ink)
                            Spacer()
                            TypeControl(selection: store.ticketType, compact: true)
                        }
                        BodyField(text: $store.field, font: .system(size: 14))
                            .frame(height: 188)
                        HStack(spacing: 7) {
                            ForEach(store.material) { item in
                                HStack(spacing: 5) {
                                    Image(systemName: item.glyph)
                                        .font(.system(size: 10)).foregroundStyle(Ink.faint)
                                    Text(item.name).font(.system(size: 10))
                                        .foregroundStyle(Ink.dim)
                                }
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(Ink.canvas)
                                .clipShape(Capsule())
                            }
                            Press(title: "Attach", glyph: "paperclip", kind: .quiet)
                            Spacer()
                        }
                        HStack(spacing: 9) {
                            Press(title: store.voice == .listening ? "Stop" : "Speak",
                                  glyph: "mic.fill") {
                                store.voice = store.voice == .listening
                                    ? .transcribing
                                    : .listening
                            }
                            Spacer()
                            Press(title: "Generate", glyph: "sparkles", kind: .primary) {
                                Task { await store.generate() }
                            }
                        }
                    }
                    .padding(18)
                }
                .frame(width: 660)
                .background(Ink.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(Ink.rule, lineWidth: 1) }
                .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
                Spacer()
                Spacer()
            }
        }
    }

    /// Shared footer for the two windowed pre-Generate styles. Submit is absent by design —
    /// there is nothing to submit until a Draft exists.
    private var preGenerateFooter: some View {
        HStack(spacing: 9) {
            Press(title: store.voice == .listening ? "Stop" : "Speak", glyph: "mic.fill") {
                store.voice = store.voice == .listening ? .transcribing : .listening
            }
            Text(store.voice == .listening
                ? "Take appends into the field"
                : "Generate is a separate press")
                .font(.system(size: 10)).foregroundStyle(Ink.faint)
            Spacer()
            Press(title: "Generate", glyph: "sparkles", kind: .primary) {
                Task { await store.generate() }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Ink.canvas)
    }

    // MARK: - Surface picker

    private var surfacePicker: some View {
        VStack(spacing: 6) {
            ForEach(Surface.allCases, id: \.self) { surface in
                Button { store.surface = surface } label: {
                    VStack(spacing: 3) {
                        Image(systemName: glyph(surface))
                            .font(.system(size: 14, weight: .medium))
                        Text(surface.label).font(.system(size: 8, weight: .medium))
                    }
                    .foregroundStyle(surface == store.surface ? Ink.accent : Ink.faint)
                    .frame(width: 44, height: 40)
                    .background(surface == store.surface ? Ink.canvas : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("FAK").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.faint)
                .padding(.bottom, 10)
        }
        .padding(.top, 10)
        .frame(width: 52)
        .background(Ink.panel)
    }

    private func glyph(_ surface: Surface) -> String {
        switch surface {
        case .create: "square.and.pencil"
        case .batch: "list.bullet.rectangle"
        case .rewrite: "arrow.triangle.2.circlepath"
        }
    }

    // MARK: - Rail

    @ViewBuilder private var rail: some View {
        switch store.surface {
        case .create: createRail
        case .batch: batchRail
        case .rewrite: rewriteRail
        }
    }

    /// Material only. Before Generate there are no Related hits and no duplicate — matching
    /// happens after Generate (§10), so the rail must not pretend otherwise.
    private var materialRail: some View {
        VStack(spacing: 0) {
            PaneTitle("Material") { Press(title: "Attach", glyph: "plus", kind: .quiet) }
            materialRows
            Spacer()
            HRule()
            catalogFooter
        }
        .background(Ink.panel)
    }

    private var materialRows: some View {
        VStack(spacing: 0) {
            ForEach(store.material) { item in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: item.glyph).font(.system(size: 10.5))
                        .foregroundStyle(Ink.faint).frame(width: 13).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.system(size: 10.5)).foregroundStyle(Ink.ink)
                        Text(item.note).font(.system(size: 9)).foregroundStyle(Ink.faint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
    }

    private var createRail: some View {
        VStack(spacing: 0) {
            PaneTitle("Material") { Press(title: "Attach", glyph: "plus", kind: .quiet) }
            materialRows
            HRule()
            PaneTitle("Related") {
                Text("cap 3").font(.system(size: 9)).foregroundStyle(Ink.faint)
            }
            VStack(spacing: 0) {
                ForEach(store.related, id: \.key) { row in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: store.relatedTicked.contains(row.key.value)
                            ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10.5))
                            .foregroundStyle(store.relatedTicked.contains(row.key.value)
                                ? Ink.accent : Ink.faint)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.key.value)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.faint)
                            Text(row.shortLabel ?? row.title).font(.system(size: 10.5))
                                .foregroundStyle(Ink.ink).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                Text("Ticking one sends it to the next turn as Context. Nothing is written.")
                    .font(.system(size: 9)).foregroundStyle(Ink.faint)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            Spacer()
            HRule()
            catalogFooter
        }
        .background(Ink.panel)
    }

    private var catalogFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: store.catalogRefreshFailed
                ? "exclamationmark.arrow.triangle.2.circlepath" : "checkmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(store.catalogRefreshFailed ? Ink.warn : Ink.go)
            Text(store.catalogRefreshFailed
                ? "Catalog snapshot 14:02 · refresh failed"
                : "Catalog fresh · \(store.catalog.rows.count) rows")
                .font(.system(size: 9.5))
                .foregroundStyle(store.catalogRefreshFailed ? Ink.warn : Ink.dim)
            Spacer(minLength: 0)
            if store.catalogRefreshFailed {
                Button {} label: {
                    Text("Retry").font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Ink.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(store.catalogRefreshFailed ? Ink.warnFill : Ink.panel)
    }

    private var batchRail: some View {
        VStack(spacing: 0) {
            PaneTitle("Batch") { Press(title: "Add", glyph: "plus", kind: .quiet) }
            HStack(spacing: 6) {
                LineField(text: $store.batchName, font: .system(size: 12, weight: .medium),
                          bordered: false)
                Text("\(store.batchDrafts.count) Drafts")
                    .font(.system(size: 9.5)).foregroundStyle(Ink.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            HRule()
            Scroll {
                VStack(spacing: 0) {
                    ForEach(Array(store.batchDrafts.enumerated()), id: \.element.id) { i, draft in
                        Button { store.batchFocus = i } label: {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(spacing: 2) {
                                    Text("\(i + 1)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Ink.faint)
                                    if i < store.batchDrafts.count - 1 && !store.batchChainCleared {
                                        Rectangle().fill(Ink.rule).frame(width: 1, height: 22)
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(Ink.faint)
                                    }
                                }
                                .frame(width: 12)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.shortLabel)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Ink.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 5) {
                                        TypeTag(type: draft.ticketType)
                                        Text(draft.epic).font(.system(size: 9.5))
                                            .foregroundStyle(Ink.faint).lineLimit(1)
                                    }
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(draft.isComplete ? Ink.go : Ink.warn)
                                            .frame(width: 5, height: 5)
                                        Text(draft.isComplete
                                            ? "complete"
                                            : "\(draft.openQuestionCount) open")
                                            .font(.system(size: 9))
                                            .foregroundStyle(draft.isComplete ? Ink.go : Ink.warn)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(i == store.batchFocus ? Ink.canvas : .clear)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(i == store.batchFocus ? Ink.accent : .clear)
                                    .frame(width: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HRule()
            HStack(spacing: 6) {
                Text("blocks order").font(.system(size: 9.5)).foregroundStyle(Ink.faint)
                Spacer()
                Press(title: "Reorder", kind: .quiet)
                Press(title: "No links", kind: .quiet)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Ink.canvas)
        }
        .background(Ink.panel)
    }

    private var rewriteRail: some View {
        VStack(spacing: 0) {
            PaneTitle("Improve existing")
            HStack(spacing: 6) {
                LineField(text: $store.rewriteKey, placeholder: "FAK-000",
                          font: .system(size: 12, design: .monospaced))
                    .frame(width: 88)
                Press(title: "Fetch", kind: .normal)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            if store.rewriteStale {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 10))
                        .foregroundStyle(Ink.warn)
                    Text("Jira changed since the 14:31 fetch.")
                        .font(.system(size: 10)).foregroundStyle(Ink.dim)
                    Button {} label: {
                        Text("Re-fetch").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Ink.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Ink.warnFill)
            }
            HRule()
            Scroll {
                VStack(alignment: .leading, spacing: 9) {
                    FieldLabel(text: "Live body · Material")
                    Text(Fixtures.rewriteLiveBody).font(.system(size: 10.5))
                        .foregroundStyle(Ink.dim).fixedSize(horizontal: false, vertical: true)
                    HRule()
                    FieldLabel(text: "Comments · 3, newest first")
                    ForEach(Fixtures.rewriteComments.reversed(), id: \.self) { comment in
                        Text(comment).font(.system(size: 10.5)).foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 7)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Ink.rule).frame(width: 2)
                            }
                    }
                    Text("Fakthis never writes a Jira comment.")
                        .font(.system(size: 9)).foregroundStyle(Ink.faint)
                }
                .padding(12)
            }
        }
        .background(Ink.panel)
    }

    // MARK: - Draft column

    private var draftColumn: some View {
        VStack(spacing: 0) {
            PaneTitle(store.surface == .batch
                ? "Draft \(store.batchFocus + 1) of \(store.batchDrafts.count)"
                : "Draft") {
                HStack(spacing: 9) {
                    Text(store.epicName).font(.system(size: 10.5)).foregroundStyle(Ink.dim)
                    TypeControl(selection: store.ticketType, compact: true) { type in
                        Task { await store.changeTicketType(type) }
                    }
                }
            }
            Scroll {
                VStack(alignment: .leading, spacing: 13) {
                    LineField(text: $store.shortLabel,
                              font: .system(size: 12.5, weight: .medium), bordered: false)
                    LineField(text: $store.title, font: .system(size: 18, weight: .semibold),
                              bordered: false)
                    HRule()
                    if store.descriptionWasHandEdited {
                        RegenerateOffer(
                            onRegenerate: { Task { await store.regenerateDefinitionOfDone() } },
                            onKeep: { store.descriptionWasHandEdited = false }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    BodyField(text: $store.body, font: .system(size: 12.5)) {
                        store.descriptionWasHandEdited = true
                        store.pushEditsIntoStructuralCheck()
                    }
                    .frame(height: 178)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Definition of Done")
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Ink.ink)
                        ForEach(store.dodBullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 7) {
                                Text("•").font(.system(size: 12)).foregroundStyle(Ink.faint)
                                Text(bullet).font(.system(size: 12)).foregroundStyle(Ink.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !store.openQuestions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("Open questions")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Ink.ink)
                                Text("marked `fakthis-open-questions` at Submit")
                                    .font(.system(size: 10)).foregroundStyle(Ink.warn)
                            }
                            ForEach(store.openQuestions, id: \.self) { question in
                                HStack(alignment: .top, spacing: 7) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 10.5)).foregroundStyle(Ink.warn)
                                        .padding(.top, 1)
                                    Text(question).font(.system(size: 11.5))
                                        .foregroundStyle(Ink.dim)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Press(title: "Answer", kind: .quiet)
                                }
                            }
                        }
                    }
                    if store.surface == .rewrite && store.rewriteDiffOpen {
                        VStack(alignment: .leading, spacing: 6) {
                            HRule()
                            Text("Diff against live \(store.rewriteKey)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Ink.ink)
                            DiffView(before: Fixtures.rewriteLiveBody, after: store.body)
                                .background(Ink.sunken)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .padding(.trailing, 22)
            }
            HRule()
            footer
        }
        .background(Ink.panel)
        .overlay(alignment: .trailing) { gutter }
    }

    /// One mark per warn-not-block signal, down the edge of the Draft. Opening the panel pushes
    /// the Draft narrower — it never covers it.
    private var gutter: some View {
        VStack(spacing: 5) {
            Button { signalsExpanded.toggle() } label: {
                Image(systemName: signalsExpanded
                    ? "chevron.right"
                    : "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(store.signals.isEmpty ? Ink.faint : Ink.warn)
                    .frame(width: 20, height: 18)
            }
            .buttonStyle(.plain)
            ForEach(store.signals) { signal in
                Image(systemName: signal.kind.glyph)
                    .font(.system(size: 9))
                    .foregroundStyle(Ink.warn)
                    .frame(width: 20, height: 17)
                    .background(Ink.warnFill)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
        }
        .padding(.top, 40)
        .frame(width: 22)
        .background(Ink.canvas.opacity(0.6))
    }

    private var signalPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("SIGNALS").font(.system(size: 9.5, weight: .bold)).tracking(0.8)
                    .foregroundStyle(Ink.faint)
                SignalCount(count: store.signals.count)
                Spacer()
                Button { signalsExpanded = false } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Ink.faint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Ink.canvas)
            HRule()
            Scroll {
                VStack(spacing: 0) {
                    ForEach(store.signals) { signal in
                        SignalRow(signal: signal)
                        HRule()
                    }
                }
            }
            Text("None of these block Submit.")
                .font(.system(size: 9.5)).foregroundStyle(Ink.faint)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.canvas)
        }
        .background(Ink.panel)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if store.surface == .batch {
                Text("Submit writes all \(store.batchDrafts.count) in blocks order")
                    .font(.system(size: 10)).foregroundStyle(Ink.faint)
            } else if store.surface == .rewrite {
                Text("Watchers of \(store.rewriteKey) are emailed")
                    .font(.system(size: 10)).foregroundStyle(Ink.faint)
            } else if !store.openQuestions.isEmpty {
                Text("Submits with `fakthis-open-questions`")
                    .font(.system(size: 10)).foregroundStyle(Ink.warn)
            }
            Spacer()
            switch store.surface {
            case .create:
                Press(title: "Submit", glyph: "arrow.up.forward", kind: .primary) {
                    Task { await store.submit() }
                }
            case .batch:
                Press(title: "Submit Batch (\(store.batchDrafts.count))",
                      glyph: "arrow.up.forward", kind: .primary)
            case .rewrite:
                Press(title: "Update \(store.rewriteKey)",
                      glyph: "arrow.up.forward", kind: .primary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Ink.canvas)
    }

    // MARK: - Conversation column, now collapsible

    @ViewBuilder private var conversationColumn: some View {
        if store.conversationCollapsed {
            collapsedConversation(note: store.chat.isEmpty
                ? "No chat on this Draft"
                : "\(store.chat.count) turns")
        } else {
            conversation.frame(width: 316)
        }
    }

    /// A 46pt spine. Rewrite opens collapsed — §12 allows Update without ever pressing Generate,
    /// so the conversation is owed no width until there is a conversation.
    private func collapsedConversation(note: String) -> some View {
        VStack(spacing: 10) {
            Button { store.conversationCollapsed = false } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.faint)
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)
            Circle()
                .fill(store.voice == .listening ? Ink.danger : Ink.faint)
                .frame(width: 6, height: 6)
            Text(note)
                .font(.system(size: 9.5))
                .foregroundStyle(Ink.faint)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(width: 20, height: 130)
                .padding(.top, 40)
            Spacer()
        }
        .padding(.top, 12)
        .frame(width: 46)
        .background(Ink.panel)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { store.conversationCollapsed = true } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.faint)
                        .frame(width: 24, height: 26)
                }
                .buttonStyle(.plain)
                VoiceStrip(
                    phase: store.voice,
                    gesture: store.hasDraft ? "hold ⌥" : "⌥ toggle",
                    compileInProgress: store.aneCompileInProgress
                )
            }
            .background(Ink.panel)
            Scroll {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.chat) { turn in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(turn.role == .agent ? "Agent" : "You")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(turn.role == .agent ? Ink.accent : Ink.faint)
                            Text(turn.text).font(.system(size: 11.5)).foregroundStyle(Ink.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(turn.role == .agent ? Ink.sunken : Ink.canvas)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    if let duplicate = store.duplicateHit {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("This looks like \(duplicate.key.value) — "
                                + "\(duplicate.shortLabel ?? duplicate.title).")
                                .font(.system(size: 11)).foregroundStyle(Ink.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 7) {
                                Press(title: "Work on \(duplicate.key.value)", kind: .quiet)
                                Press(title: "Continue", kind: .normal) {
                                    store.duplicateDismissed = true
                                }
                            }
                        }
                        .padding(9)
                        .background(Ink.warnFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(12)
            }
            HRule()
            VStack(alignment: .leading, spacing: 7) {
                BodyField(text: $store.field, font: .system(size: 12)).frame(height: 60)
                HStack(spacing: 7) {
                    Press(title: store.voice == .listening ? "Stop" : "Speak", glyph: "mic.fill") {
                        store.voice = store.voice == .listening ? .transcribing : .listening
                    }
                    Spacer()
                    Press(title: "Send", kind: .primary) { Task { await store.send() } }
                }
            }
            .padding(11)
            .background(Ink.canvas)
        }
        .background(Ink.panel)
    }
}
