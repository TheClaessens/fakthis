// THROWAWAY PROTOTYPE — Variant A, "Workbench".
//
// ONE window. Two panes: conversation left, Draft right. Surface is a segmented control in the
// toolbar; Batch adds a third column, Rewrite swaps the left pane's contents. Warn-not-block
// signals live in a docked tray along the bottom of the Draft pane.

import SwiftUI
import Fakthis

struct VariantA: View {
    @Bindable var store: Store

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HRule()
            if store.surface == .batch {
                ChainStrip(drafts: store.batchDrafts, cleared: store.batchChainCleared)
                HRule()
            }
            HStack(spacing: 0) {
                if store.surface == .batch {
                    siblingList.frame(width: 236)
                    VRule()
                }
                leftPane.frame(width: 348)
                VRule()
                draftPane
            }
        }
        .background(Ink.canvas)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12)).foregroundStyle(Ink.accent)
                Text("FAK").font(.system(size: 12.5, weight: .semibold))
                Text(store.surface == .batch ? store.batchName : store.epicName)
                    .font(.system(size: 11)).foregroundStyle(Ink.dim)
            }
            Spacer()
            HStack(spacing: 0) {
                ForEach(Surface.allCases, id: \.self) { surface in
                    Button { store.surface = surface } label: {
                        Text(surface.label)
                            .font(.system(size: 11.5,
                                          weight: surface == store.surface ? .semibold : .regular))
                            .foregroundStyle(surface == store.surface ? .white : Ink.dim)
                            .padding(.horizontal, 13).padding(.vertical, 4)
                            .background(surface == store.surface ? Ink.ink : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2).background(Ink.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(Ink.rule, lineWidth: 1) }
            Spacer()
            SignalCount(count: store.signals.count)
            submitButton
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Ink.panel)
    }

    private var submitButton: some View {
        Group {
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

    // MARK: Left pane

    private var leftPane: some View {
        VStack(spacing: 0) {
            VoiceStrip(
                phase: store.voice,
                gesture: store.hasDraft ? "hold ⌥ to talk" : "⌥ to start / stop",
                compileInProgress: store.aneCompileInProgress
            )
            if store.surface == .rewrite {
                rewriteMaterial
            } else {
                conversation
            }
            HRule()
            materialList
        }
        .background(Ink.panel)
    }

    private var conversation: some View {
        Scroll {
            VStack(alignment: .leading, spacing: 10) {
                if !store.hasDraft {
                    FieldLabel(text: "Brain-dump")
                }
                ForEach(store.chat) { turn in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(turn.role == .agent ? "Agent" : "You")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(turn.role == .agent ? Ink.accent : Ink.faint)
                        Text(turn.text)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(turn.role == .agent ? Ink.sunken : Ink.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                composer
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            BodyField(text: $store.field)
                .frame(height: store.hasDraft ? 62 : 148)
            HStack(spacing: 7) {
                Press(title: store.voice == .listening ? "Stop" : "Speak",
                      glyph: "mic.fill",
                      kind: .normal) {
                    store.voice = store.voice == .listening ? .transcribing : .listening
                }
                Spacer()
                if store.hasDraft {
                    Press(title: "Send", kind: .primary) { Task { await store.send() } }
                } else {
                    Press(title: "Generate", glyph: "sparkles", kind: .primary) {
                        Task { await store.generate() }
                    }
                }
            }
        }
    }

    private var rewriteMaterial: some View {
        Scroll {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    FieldLabel(text: "Improve existing")
                    LineField(text: $store.rewriteKey, placeholder: "FAK-000",
                              font: .system(size: 12, design: .monospaced))
                        .frame(width: 92)
                    Press(title: "Fetch", kind: .normal)
                }
                Text("LIVE BODY · fetched 14:31")
                    .font(.system(size: 9, weight: .bold)).tracking(0.7)
                    .foregroundStyle(Ink.faint)
                Text(Fixtures.rewriteLiveBody)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.sunken)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("COMMENTS · 3, newest first")
                    .font(.system(size: 9, weight: .bold)).tracking(0.7)
                    .foregroundStyle(Ink.faint)
                ForEach(Fixtures.rewriteComments.reversed(), id: \.self) { comment in
                    Text(comment)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ink.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Ink.rule).frame(width: 2)
                        }
                }
                composer
            }
            .padding(12)
        }
    }

    private var materialList: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Material") {
                Press(title: "Attach", glyph: "plus", kind: .quiet)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.material) { item in
                    HStack(spacing: 7) {
                        Image(systemName: item.glyph)
                            .font(.system(size: 10)).foregroundStyle(Ink.faint).frame(width: 13)
                        Text(item.name).font(.system(size: 10.5)).foregroundStyle(Ink.ink)
                        Spacer(minLength: 4)
                        Text(item.note).font(.system(size: 9)).foregroundStyle(Ink.faint)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                }
            }
            .padding(.vertical, 3)
        }
        .background(Ink.panel)
    }

    // MARK: Draft pane

    private var draftPane: some View {
        VStack(spacing: 0) {
            PaneTitle(store.surface == .batch
                ? "Draft \(store.batchFocus + 1) of \(store.batchDrafts.count)"
                : "Draft") {
                HStack(spacing: 8) {
                    Text(store.epicName).font(.system(size: 10.5)).foregroundStyle(Ink.dim)
                    TypeControl(selection: store.ticketType, compact: true) { type in
                        Task { await store.changeTicketType(type) }
                    }
                }
            }
            Scroll {
                VStack(alignment: .leading, spacing: 13) {
                    field("Short label") {
                        LineField(text: $store.shortLabel, font: .system(size: 13, weight: .medium))
                    }
                    field("Title") {
                        LineField(text: $store.title, font: .system(size: 14))
                    }
                    field("Description") {
                        VStack(spacing: 0) {
                            if store.descriptionWasHandEdited {
                                RegenerateOffer(
                                    onRegenerate: { Task { await store.regenerateDefinitionOfDone() } },
                                    onKeep: { store.descriptionWasHandEdited = false }
                                )
                            }
                            BodyField(text: $store.body) {
                                store.descriptionWasHandEdited = true
                                store.pushEditsIntoStructuralCheck()
                            }
                            .frame(height: 168)
                        }
                    }
                    field("Definition of Done") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(store.dodBullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 7) {
                                    Text("•").font(.system(size: 12)).foregroundStyle(Ink.faint)
                                    Text(bullet).font(.system(size: 12)).foregroundStyle(Ink.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.sunken)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    if !store.openQuestions.isEmpty {
                        field("Open questions") {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(store.openQuestions, id: \.self) { question in
                                    HStack(alignment: .top, spacing: 7) {
                                        Image(systemName: "questionmark.circle")
                                            .font(.system(size: 10)).foregroundStyle(Ink.warn)
                                        Text(question).font(.system(size: 11.5))
                                            .foregroundStyle(Ink.dim)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    if store.surface == .rewrite && store.rewriteDiffOpen {
                        field("Diff against live \(store.rewriteKey)") {
                            VStack(alignment: .leading, spacing: 0) {
                                DiffView(before: Fixtures.rewriteLiveBody, after: store.body)
                            }
                            .padding(.vertical, 4)
                            .background(Ink.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5).stroke(Ink.rule, lineWidth: 1)
                            }
                        }
                    }
                }
                .padding(14)
            }
            HRule()
            signalTray
        }
        .background(Ink.panel)
    }

    private func field<T: View>(_ label: String, @ViewBuilder content: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FieldLabel(text: label)
            content()
        }
    }

    private var signalTray: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(Ink.faint)
                Text("SIGNALS").font(.system(size: 9.5, weight: .bold)).tracking(0.8)
                    .foregroundStyle(Ink.faint)
                SignalCount(count: store.signals.count)
                Spacer()
                Text("None of these block Submit")
                    .font(.system(size: 9.5)).foregroundStyle(Ink.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Ink.canvas)
            if store.signals.isEmpty {
                Text("Nothing to flag.")
                    .font(.system(size: 10.5)).foregroundStyle(Ink.faint)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                Scroll {
                    VStack(spacing: 0) {
                        ForEach(store.signals) { signal in
                            SignalRow(signal: signal)
                            HRule()
                        }
                    }
                }
                .frame(maxHeight: 186)
            }
        }
        .background(Ink.panel)
    }

    // MARK: Batch sibling list

    private var siblingList: some View {
        VStack(spacing: 0) {
            PaneTitle("Batch · \(store.batchDrafts.count)") {
                Press(title: "Add", glyph: "plus", kind: .quiet)
            }
            Scroll {
                VStack(spacing: 0) {
                    ForEach(Array(store.batchDrafts.enumerated()), id: \.element.id) { i, draft in
                        Button { store.batchFocus = i } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 5) {
                                    Text("\(i + 1)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Ink.faint)
                                    Text(draft.shortLabel)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Ink.ink)
                                    Spacer(minLength: 2)
                                    if !draft.isComplete {
                                        Image(systemName: "questionmark.circle.fill")
                                            .font(.system(size: 9)).foregroundStyle(Ink.warn)
                                    }
                                }
                                HStack(spacing: 5) {
                                    TypeTag(type: draft.ticketType)
                                    Text(draft.epic).font(.system(size: 9.5))
                                        .foregroundStyle(Ink.faint).lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(i == store.batchFocus ? Ink.canvas : .clear)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(i == store.batchFocus ? Ink.accent : .clear)
                                    .frame(width: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        HRule()
                    }
                }
            }
        }
        .background(Ink.panel)
    }
}
