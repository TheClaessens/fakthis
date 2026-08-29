// THROWAWAY PROTOTYPE. Shared primitives.
//
// ImageRenderer cannot draw AppKit-backed controls, so everything here is hand-drawn SwiftUI
// and renders identically in the running app and in a screenshot. The two exceptions are the
// text-entry primitives (`LineField`, `BodyField`): live they are a real TextField/TextEditor,
// under `\.shooting` they fall back to Text with the same metrics.

import SwiftUI
import Fakthis

extension EnvironmentValues {
    @Entry var shooting = false
}

enum Ink {
    static let canvas = Color(white: 0.95)
    static let panel = Color.white
    static let sunken = Color(white: 0.975)
    static let rule = Color(white: 0.86)
    static let ink = Color(white: 0.11)
    static let dim = Color(white: 0.46)
    static let faint = Color(white: 0.62)
    static let accent = Color(red: 0.18, green: 0.40, blue: 0.88)
    static let warn = Color(red: 0.72, green: 0.47, blue: 0.02)
    static let warnFill = Color(red: 0.99, green: 0.96, blue: 0.87)
    static let danger = Color(red: 0.75, green: 0.22, blue: 0.18)
    static let go = Color(red: 0.13, green: 0.55, blue: 0.30)
    static let addFill = Color(red: 0.90, green: 0.97, blue: 0.91)
    static let cutFill = Color(red: 0.99, green: 0.92, blue: 0.92)
}

// MARK: - Text entry

struct LineField: View {
    @Environment(\.shooting) private var shooting
    var text: Binding<String>
    var placeholder = ""
    var font: Font = .system(size: 13)
    var bordered = true

    var body: some View {
        Group {
            if shooting {
                Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                    .font(font)
                    .foregroundStyle(text.wrappedValue.isEmpty ? Ink.faint : Ink.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, bordered ? 7 : 0)
                    .padding(.vertical, bordered ? 5 : 0)
            } else {
                TextField(placeholder, text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(font)
                    .padding(.horizontal, bordered ? 7 : 0)
                    .padding(.vertical, bordered ? 5 : 0)
            }
        }
        .background(bordered ? Ink.sunken : .clear)
        .overlay {
            if bordered {
                RoundedRectangle(cornerRadius: 5).stroke(Ink.rule, lineWidth: 1)
            }
        }
    }
}

struct BodyField: View {
    @Environment(\.shooting) private var shooting
    var text: Binding<String>
    var font: Font = .system(size: 12.5)
    var onEdit: () -> Void = {}

    var body: some View {
        Group {
            if shooting {
                Text(text.wrappedValue)
                    .font(font)
                    .foregroundStyle(Ink.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            } else {
                TextEditor(text: text)
                    .font(font)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .onChange(of: text.wrappedValue) { _, _ in onEdit() }
            }
        }
        .background(Ink.sunken)
        .overlay { RoundedRectangle(cornerRadius: 5).stroke(Ink.rule, lineWidth: 1) }
    }
}

// MARK: - Buttons

struct Press: View {
    var title: String
    var glyph: String?
    var kind: Kind = .normal
    var action: () -> Void = {}

    enum Kind { case primary, normal, quiet, danger }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let glyph { Image(systemName: glyph).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: kind == .primary ? .semibold : .regular))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(kind == .normal ? Ink.rule : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .normal: Ink.ink
        case .quiet: Ink.dim
        case .danger: Ink.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Ink.accent
        case .normal: Ink.panel
        case .quiet: .clear
        case .danger: .clear
        }
    }
}

// MARK: - Ticket type

/// Ticket type as an editable control (§7.2). Hand-drawn so it renders in a screenshot.
struct TypeControl: View {
    var selection: TicketType
    var compact = false
    var onChange: (TicketType) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            ForEach([TicketType.story, .bug, .chore], id: \.self) { type in
                Button { onChange(type) } label: {
                    Text(type.label)
                        .font(.system(size: compact ? 10.5 : 11.5,
                                      weight: type == selection ? .semibold : .regular))
                        .foregroundStyle(type == selection ? Color.white : Ink.dim)
                        .padding(.horizontal, compact ? 7 : 11)
                        .padding(.vertical, compact ? 2.5 : 4)
                        .background(type == selection ? Ink.ink : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Ink.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(Ink.rule, lineWidth: 1) }
    }
}

struct TypeTag: View {
    var type: TicketType
    var body: some View {
        Text(type.label.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Ink.dim)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Ink.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Voice (§6)

/// listening / transcribing / agent thinking / your turn. A strip, never a sound.
struct VoiceStrip: View {
    var phase: VoicePhase
    var gesture: String
    var compileInProgress: Bool
    var orientation: Axis = .horizontal

    private let order: [VoicePhase] = [.listening, .transcribing, .thinking, .yourTurn]

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(compileInProgress ? "Preparing transcriber" : phase.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(compileInProgress ? Ink.warn : Ink.ink)
            HStack(spacing: 3) {
                ForEach(order, id: \.self) { step in
                    Capsule()
                        .fill(step == phase ? dotColor : Ink.rule)
                        .frame(width: step == phase ? 18 : 10, height: 3)
                }
            }
            Spacer(minLength: 6)
            Text(gesture)
                .font(.system(size: 10))
                .foregroundStyle(Ink.faint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Ink.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.rule).frame(height: 1) }
    }

    private var dotColor: Color {
        switch phase {
        case .idle: Ink.faint
        case .listening: Ink.danger
        case .transcribing: Ink.warn
        case .thinking: Ink.accent
        case .yourTurn: Ink.go
        }
    }
}

// MARK: - Warn-not-block signals

struct SignalRow: View {
    var signal: Signal
    var dense = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: signal.kind.glyph)
                .font(.system(size: 10.5))
                .foregroundStyle(Ink.warn)
                .frame(width: 13)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(signal.kind.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Ink.ink)
                    Text("warns, never blocks")
                        .font(.system(size: 9))
                        .foregroundStyle(Ink.faint)
                }
                Text(signal.text)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if !signal.actions.isEmpty && !dense {
                    HStack(spacing: 6) {
                        ForEach(signal.actions) { action in
                            Button {} label: {
                                Text(action.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Ink.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }
}

struct SignalCount: View {
    var count: Int
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
            Text("\(count) \(count == 1 ? "signal" : "signals")")
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(count == 0 ? Ink.faint : Ink.warn)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(count == 0 ? Ink.canvas : Ink.warnFill)
        .clipShape(Capsule())
    }
}

// MARK: - Batch chain (§11)

/// `A → B → C` as an editable strip, not a graph.
struct ChainStrip: View {
    var drafts: [BatchDraft]
    var cleared: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("blocks")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Ink.faint)
            if cleared {
                Text("No links")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
            } else {
                ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Ink.faint)
                    }
                    Text(draft.shortLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ink.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Ink.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5).stroke(Ink.rule, lineWidth: 1)
                        }
                }
            }
            Spacer(minLength: 6)
            Press(title: cleared ? "Propose order" : "No links", kind: .quiet)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Ink.canvas)
    }
}

// MARK: - Rewrite diff (§12)

struct DiffLine: Identifiable {
    let id = UUID()
    enum Kind { case same, cut, add }
    var kind: Kind
    var text: String
}

func diffLines(from before: String, to after: String) -> [DiffLine] {
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
            out.append(DiffLine(kind: .same, text: a[i])); i += 1; j += 1
        } else if table[i + 1][j] >= table[i][j + 1] {
            out.append(DiffLine(kind: .cut, text: a[i])); i += 1
        } else {
            out.append(DiffLine(kind: .add, text: b[j])); j += 1
        }
    }
    while i < a.count { out.append(DiffLine(kind: .cut, text: a[i])); i += 1 }
    while j < b.count { out.append(DiffLine(kind: .add, text: b[j])); j += 1 }
    return out.filter { !($0.kind == .same && $0.text.isEmpty) }
}

struct DiffView: View {
    var before: String
    var after: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(diffLines(from: before, to: after)) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text(glyph(line.kind))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(colour(line.kind))
                        .frame(width: 9)
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(line.kind == .same ? Ink.faint : Ink.ink)
                        .strikethrough(line.kind == .cut, color: Ink.danger.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(fill(line.kind))
            }
        }
    }

    private func glyph(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .same: " "
        case .cut: "−"
        case .add: "+"
        }
    }

    private func colour(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .same: Ink.faint
        case .cut: Ink.danger
        case .add: Ink.go
        }
    }

    private func fill(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .same: .clear
        case .cut: Ink.cutFill
        case .add: Ink.addFill
        }
    }
}

// MARK: - Chrome

struct PaneTitle: View {
    var text: String
    var trailing: AnyView?

    init(_ text: String) {
        self.text = text
        self.trailing = nil
    }

    init<T: View>(_ text: String, @ViewBuilder trailing: () -> T) {
        self.text = text
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Ink.faint)
            Spacer(minLength: 4)
            if let trailing { trailing }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Ink.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.rule).frame(height: 1) }
    }
}

struct FieldLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(Ink.faint)
    }
}

struct VRule: View {
    var body: some View { Rectangle().fill(Ink.rule).frame(width: 1) }
}

struct HRule: View {
    var body: some View { Rectangle().fill(Ink.rule).frame(height: 1) }
}

/// The Definition of Done regenerate offer (§7.3) — inline, dismissible, never a modal.
struct RegenerateOffer: View {
    var onRegenerate: () -> Void = {}
    var onKeep: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(Ink.warn)
            Text("You edited the description. Regenerate the Definition of Done?")
                .font(.system(size: 10.5))
                .foregroundStyle(Ink.ink)
            Spacer(minLength: 4)
            Press(title: "Regenerate", kind: .quiet, action: onRegenerate)
            Press(title: "Keep", kind: .quiet, action: onKeep)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Ink.warnFill)
        .overlay(alignment: .leading) { Rectangle().fill(Ink.warn).frame(width: 2) }
    }
}

/// ScrollView is AppKit-backed and will not draw under ImageRenderer, so under `\.shooting`
/// this becomes a clipped stack. Live it is an ordinary ScrollView.
struct Scroll<Content: View>: View {
    @Environment(\.shooting) private var shooting
    @ViewBuilder var content: Content

    var body: some View {
        if shooting {
            // Color.clear accepts whatever height the parent proposes; the overlay is sized to
            // it and anything longer is clipped, exactly as a real ScrollView would show.
            Color.clear
                .overlay(alignment: .top) {
                    VStack(spacing: 0) { content }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .clipped()
        } else {
            ScrollView { content }
        }
    }
}
