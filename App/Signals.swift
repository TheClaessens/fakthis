import SwiftUI
import Fakthis

// "Warns, never blocks" (§9) is a placement problem, and the signals are **two classes, never
// one list**. One undifferentiated list is wrong at any size: it truncates, or it covers the
// Draft it is warning about. So this file holds two shapes and nothing that merges them.
//
// Field signals — the structural check, the Definition of Done offer — sit at the field they
// concern, inside the Draft's scroll, where the thing they are about is.
//
// Draft signals rest as marks in a gutter down the Draft's trailing edge. The gutter is the
// resting state and what the window opens with; the panel is temporary.

/// The structural check, beside the field it is about.
///
/// It is drawn as prose under the field rather than as rows in a box, because a box next to one
/// field is a list again — a list of one, which is the shape §9 rejects at every size.
struct FieldWarnings: View {
    var warnings: [StructuralWarning]

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(warnings) { warning in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text(warning.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.orange)
        }
    }
}

/// The Definition of Done regenerate offer, **above** the description.
///
/// Above, because it is attached to what changed rather than orphaned below it: the second pass
/// read the description as it was before the hand-edit, and the bar sits where the reader's eye
/// meets the text it is now out of date with. It **re-arms** — `Session` arms it on every
/// hand-edit, so Keep answers the edit that raised it and not the one after — and it never
/// regenerates silently (§7.3).
struct DefinitionOfDoneOffer: View {
    var regenerate: () async -> Void
    var keep: () async -> Void
    var working: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("The description changed. Regenerate the Definition of Done?")
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

/// The resting state: one mark per Draft signal, down the Draft's trailing edge.
///
/// Each mark carries its signal's own text as a tooltip, so a single low-value signal is legible
/// from the gutter without opening the panel and taking width off the Draft to read one line.
/// Pressing a mark opens the panel, which is the only thing the panel is for: the ones that carry
/// an action, and the ones there are too many of to read one hover at a time.
///
/// A continued duplicate also rests here, as a mark that is **not** a signal: it does not open
/// the panel and it is never listed in it. The interrupt in the conversation is the other home;
/// Session never sets both at once.
struct SignalGutter: View {
    var signals: [DraftSignal]
    var duplicateMark: DuplicateHit?
    @Binding var open: Bool

    var body: some View {
        VStack(spacing: 6) {
            if let hit = duplicateMark {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(width: 22, height: 22)
                    .help(hit.markText)
                    .accessibilityLabel(hit.markText)
            }
            ForEach(signals) { signal in
                Button {
                    open = true
                } label: {
                    Image(systemName: signal.glyph)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(signal.text)
                .accessibilityLabel(signal.text)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(width: 26)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) {
            // The edge, drawn. Without it the marks float in the Draft's own margin and read as
            // decoration on the text rather than as a strip beside it.
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
    }
}

/// The temporary state: the same signals, readable, with the actions the upload one has.
///
/// It **displaces** rather than overlays — it is a sibling of the Draft's scroll, not a layer
/// over it — so nothing about the Draft is covered and the footer keeps Submit reachable. Its
/// height follows its content: one signal is one row tall, never a full-height column of white
/// space beside a single line.
struct SignalPanel: View {
    var signals: [DraftSignal]
    var working: Bool
    var retryUploads: () async -> Void
    var skipUploads: () async -> Void
    @Binding var open: Bool

    var body: some View {
        // A card with nothing under it, rather than a column with white space under it. The
        // `Spacer` is what makes the height follow the content: the box ends where the signals
        // do, and the rest of the strip is the Draft column's own ground.
        VStack(spacing: 0) {
            card
            Spacer(minLength: 0)
        }
        .frame(width: 250)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(signals) { signal in
                row(signal)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
        .padding(.horizontal, 9)
        .padding(.top, 13)
    }

    private var header: some View {
        HStack {
            Text("Signals")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                open = false
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close the signals")
        }
    }

    @ViewBuilder
    private func row(_ signal: DraftSignal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: signal.glyph)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(signal.text)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // Only the upload signal has anything to press: a Ticket that is already live and a
            // queue that can be retried or dropped. The other two are facts about the Draft.
            if signal.kind == .upload {
                HStack(spacing: 6) {
                    Button("Retry") { Task { await retryUploads() } }
                    Button("Skip") { Task { await skipUploads() } }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(working)
            }
        }
    }
}

extension DraftSignal {
    /// One glyph per class, so two marks resting together are told apart before either is read.
    var glyph: String {
        switch kind {
        case .catalog: "clock.badge.exclamationmark"
        case .material: "paperclip.badge.ellipsis"
        case .upload: "exclamationmark.arrow.triangle.2.circlepath"
        }
    }
}
