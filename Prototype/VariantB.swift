// THROWAWAY PROTOTYPE — Variant B, "Desk".
//
// SEPARATE surfaces. Create, Batch and Rewrite are each their own window opened from a Project
// home; the frame behind is another open window. Inside a window there are no panes at all —
// one vertical scroll, the Draft as a document in a measured column, the chat log underneath
// it, a composer docked to the bottom. Warn-not-block signals are anchored inline at the thing
// they are about, not collected anywhere.

import SwiftUI
import Fakthis

struct VariantB: View {
    @Bindable var store: Store

    var body: some View {
        ZStack {
            Ink.canvas
            behindWindow
            window
                .padding(.leading, 34).padding(.top, 26)
                .padding(.trailing, 12).padding(.bottom, 10)
        }
    }

    /// A second open window, to make "these are separate windows" legible in a still.
    private var behindWindow: some View {
        VStack(spacing: 0) {
            titleBar(for: otherSurface, active: false)
            Rectangle().fill(Ink.panel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(Ink.rule, lineWidth: 1) }
        .padding(.trailing, 40).padding(.bottom, 34)
        .padding(.leading, 14).padding(.top, 12)
    }

    private var otherSurface: Surface {
        store.surface == .create ? .batch : .create
    }

    private var window: some View {
        VStack(spacing: 0) {
            titleBar(for: store.surface, active: true)
            HRule()
            scroll
            HRule()
            dock
        }
        .background(Ink.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(Ink.rule, lineWidth: 1) }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
    }

    private func titleBar(for surface: Surface, active: Bool) -> some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach([Ink.danger, Ink.warn, Ink.go], id: \.self) { colour in
                    Circle().fill(active ? colour : Ink.rule).frame(width: 9, height: 9)
                }
                Spacer()
                if active {
                    SignalCount(count: store.signals.count)
                    Press(title: "Windows", glyph: "square.grid.2x2", kind: .quiet)
                }
            }
            HStack(spacing: 6) {
                Text(title(for: surface))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(active ? Ink.ink : Ink.faint)
                Text("— FAK").font(.system(size: 11.5)).foregroundStyle(Ink.faint)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(active ? Ink.canvas : Ink.sunken)
    }

    private func title(for surface: Surface) -> String {
        switch surface {
        case .create: "New Ticket"
        case .batch: "Batch · \(store.batchName)"
        case .rewrite: "Rewrite \(store.rewriteKey.isEmpty ? "…" : store.rewriteKey)"
        }
    }

    // MARK: The scroll

    private var scroll: some View {
        Scroll {
            VStack(alignment: .leading, spacing: 0) {
                if store.surface == .batch { chainCards }
                if store.surface == .rewrite { rewriteMaterial }
                column {
                    VStack(alignment: .leading, spacing: 14) {
                        if let duplicate = store.duplicateHit { interrupt(duplicate) }
                        documentHead
                        descriptionBlock
                        definitionOfDone
                        openQuestions
                        if store.surface == .rewrite && store.rewriteDiffOpen { diffBlock }
                        uploadsNote
                        if !store.chat.isEmpty { chatLog }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .background(Ink.panel)
    }

    private func column<T: View>(@ViewBuilder content: () -> T) -> some View {
        HStack {
            Spacer(minLength: 0)
            content().frame(width: 618)
            Spacer(minLength: 0)
        }
    }

    private var documentHead: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                TypeControl(selection: store.ticketType) { type in
                    Task { await store.changeTicketType(type) }
                }
                LineField(text: $store.shortLabel,
                          font: .system(size: 12, weight: .medium),
                          bordered: false)
                    .frame(width: 190)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 9)).foregroundStyle(Ink.faint)
                    Text(store.epicName).font(.system(size: 10.5)).foregroundStyle(Ink.dim)
                }
            }
            if store.catalogRefreshFailed { inlineSignal(.catalog) }
            LineField(text: $store.title,
                      font: .system(size: 21, weight: .semibold),
                      bordered: false)
            ForEach(store.structuralWarnings, id: \.self) { warning in
                inlineNote(glyph: "ruler", text: "Structural check: \(warning). "
                    + "Submit is unaffected.")
            }
        }
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.descriptionWasHandEdited {
                RegenerateOffer(
                    onRegenerate: { Task { await store.regenerateDefinitionOfDone() } },
                    onKeep: { store.descriptionWasHandEdited = false }
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.bottom, 7)
            }
            BodyField(text: $store.body, font: .system(size: 13)) {
                store.descriptionWasHandEdited = true
                store.pushEditsIntoStructuralCheck()
            }
            .frame(height: 176)
        }
    }

    private var definitionOfDone: some View {
        VStack(alignment: .leading, spacing: 7) {
            HRule()
            Text("Definition of Done")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.ink)
            ForEach(store.dodBullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").font(.system(size: 13)).foregroundStyle(Ink.faint)
                    Text(bullet).font(.system(size: 12.5)).foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var openQuestions: some View {
        if !store.openQuestions.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("Open questions")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.ink)
                    Text("Submitting now marks the Ticket `fakthis-open-questions`")
                        .font(.system(size: 10)).foregroundStyle(Ink.warn)
                }
                ForEach(store.openQuestions, id: \.self) { question in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 10.5)).foregroundStyle(Ink.warn).padding(.top, 1)
                        Text(question).font(.system(size: 12)).foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Press(title: "Answer", kind: .quiet)
                    }
                }
            }
            .padding(10)
            .background(Ink.warnFill.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder private var uploadsNote: some View {
        if !store.failedUploads.isEmpty {
            inlineNote(
                glyph: "arrow.up.circle",
                text: "\(store.failedUploads.joined(separator: ", ")) could not upload. "
                    + "The Ticket is unaffected.",
                actions: ["Retry", "Skip"]
            )
        }
        ForEach(store.materialWarnings, id: \.self) { warning in
            inlineNote(glyph: "paperclip", text: warning, actions: ["Remove file"])
        }
    }

    private var chatLog: some View {
        VStack(alignment: .leading, spacing: 9) {
            HRule()
            FieldLabel(text: "Conversation")
            ForEach(store.chat) { turn in
                HStack(alignment: .top, spacing: 9) {
                    Text(turn.role == .agent ? "Agent" : "You")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(turn.role == .agent ? Ink.accent : Ink.faint)
                        .frame(width: 38, alignment: .leading).padding(.top, 2)
                    Text(turn.text).font(.system(size: 12)).foregroundStyle(Ink.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var diffBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text("Diff against live \(store.rewriteKey)")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.ink)
                Spacer()
                if store.rewriteStale {
                    Text("Jira changed since 14:31")
                        .font(.system(size: 10)).foregroundStyle(Ink.warn)
                    Press(title: "Re-fetch", kind: .quiet)
                }
            }
            DiffView(before: Fixtures.rewriteLiveBody, after: store.body)
                .padding(.vertical, 4)
                .background(Ink.sunken)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Batch — the sibling list and the blocks chain are the same object

    private var chainCards: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                FieldLabel(text: "Batch · blocks order")
                Spacer()
                Press(title: "No links", kind: .quiet)
                Press(title: "Add Draft", glyph: "plus", kind: .quiet)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 7)
            HStack(alignment: .top, spacing: 7) {
                ForEach(Array(store.batchDrafts.enumerated()), id: \.element.id) { i, draft in
                    if i > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Ink.faint).padding(.top, 21)
                    }
                    Button { store.batchFocus = i } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                TypeTag(type: draft.ticketType)
                                Spacer(minLength: 2)
                                Circle()
                                    .fill(draft.isComplete ? Ink.go : Ink.warn)
                                    .frame(width: 6, height: 6)
                            }
                            Text(draft.shortLabel)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Ink.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(draft.epic).font(.system(size: 9.5))
                                .foregroundStyle(Ink.faint).lineLimit(1)
                        }
                        .padding(9)
                        .frame(width: 176, alignment: .leading)
                        .background(i == store.batchFocus ? Ink.panel : Ink.sunken)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(i == store.batchFocus ? Ink.accent : Ink.rule,
                                        lineWidth: i == store.batchFocus ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.bottom, 12)
        }
        .background(Ink.canvas)
        .overlay(alignment: .bottom) { HRule() }
    }

    // MARK: Rewrite Material

    private var rewriteMaterial: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                FieldLabel(text: "Improve existing")
                LineField(text: $store.rewriteKey, placeholder: "FAK-000",
                          font: .system(size: 12, design: .monospaced))
                    .frame(width: 92)
                Press(title: "Fetch", kind: .normal)
                Spacer()
                Text("Live body and comments are Material")
                    .font(.system(size: 10)).foregroundStyle(Ink.faint)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LIVE BODY").font(.system(size: 9, weight: .bold)).tracking(0.7)
                        .foregroundStyle(Ink.faint)
                    Text(Fixtures.rewriteLiveBody).font(.system(size: 10.5))
                        .foregroundStyle(Ink.dim).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text("COMMENTS · 3").font(.system(size: 9, weight: .bold)).tracking(0.7)
                        .foregroundStyle(Ink.faint)
                    ForEach(Fixtures.rewriteComments.reversed(), id: \.self) { comment in
                        Text(comment).font(.system(size: 10.5)).foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Ink.canvas)
        .overlay(alignment: .bottom) { HRule() }
    }

    // MARK: Inline signals

    private func interrupt(_ hit: CatalogRow) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundStyle(Ink.warn)
            Text("This looks like \(hit.key.value) — \(hit.shortLabel ?? hit.title).")
                .font(.system(size: 11.5)).foregroundStyle(Ink.ink)
            Spacer(minLength: 4)
            Press(title: "Work on \(hit.key.value)", kind: .quiet)
            Press(title: "Continue", kind: .normal) { store.duplicateDismissed = true }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(Ink.warnFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(Ink.warn.opacity(0.35), lineWidth: 1) }
    }

    @ViewBuilder private func inlineSignal(_ kind: SignalKind) -> some View {
        if let signal = store.signals.first(where: { $0.kind == kind }) {
            inlineNote(glyph: kind.glyph, text: signal.text,
                       actions: signal.actions.map(\.label))
        }
    }

    private func inlineNote(glyph: String, text: String, actions: [String] = []) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: glyph).font(.system(size: 10)).foregroundStyle(Ink.warn)
                .padding(.top, 1)
            Text(text).font(.system(size: 10.5)).foregroundStyle(Ink.dim)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(actions, id: \.self) { action in
                Button {} label: {
                    Text(action).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Ink.accent)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Dock

    private var dock: some View {
        VStack(spacing: 0) {
            VoiceStrip(
                phase: store.voice,
                gesture: store.hasDraft ? "hold ⌥ to talk" : "⌥ to start / stop",
                compileInProgress: store.aneCompileInProgress
            )
            HStack(alignment: .bottom, spacing: 9) {
                Press(title: store.voice == .listening ? "Stop" : "Speak", glyph: "mic.fill") {
                    store.voice = store.voice == .listening ? .transcribing : .listening
                }
                BodyField(text: $store.field, font: .system(size: 12)).frame(height: 46)
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(store.material) { item in
                            Image(systemName: item.glyph)
                                .font(.system(size: 10)).foregroundStyle(Ink.faint)
                        }
                        Press(title: "Attach", glyph: "paperclip", kind: .quiet)
                    }
                    HStack(spacing: 7) {
                        if store.hasDraft {
                            Press(title: "Send", kind: .normal) { Task { await store.send() } }
                        } else {
                            Press(title: "Generate", glyph: "sparkles", kind: .primary) {
                                Task { await store.generate() }
                            }
                        }
                        submitButton
                    }
                }
            }
            .padding(11)
            .background(Ink.canvas)
        }
    }

    @ViewBuilder private var submitButton: some View {
        switch store.surface {
        case .create:
            Press(title: "Submit", glyph: "arrow.up.forward", kind: .primary) {
                Task { await store.submit() }
            }
        case .batch:
            Press(title: "Submit Batch (3)", glyph: "arrow.up.forward", kind: .primary)
        case .rewrite:
            Press(title: "Update \(store.rewriteKey)", glyph: "arrow.up.forward", kind: .primary)
        }
    }
}
