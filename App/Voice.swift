import SwiftUI
import Fakthis

/// listening / transcribing / agent thinking / your turn. A strip on **the field receiving
/// the take**, never a bar across the window and never a sound (§6).
struct VoiceStrip: View {
    var model: WindowModel
    var gesture: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
            Text(model.aneCompileInProgress ? "Preparing transcriber" : label)
                .font(.system(size: 11, weight: .medium))
            HStack(spacing: 3) {
                mark(.listening)
                mark(.transcribing)
                mark(.agentThinking)
                mark(.yourTurn)
            }
            Spacer(minLength: 6)
            Text(gesture)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.windowGround)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }

    private func mark(_ step: Session.Status) -> some View {
        let active = !model.aneCompileInProgress && step == model.status
        return Capsule()
            .fill(active ? dot : Color(nsColor: .separatorColor))
            .frame(width: active ? 18 : 10, height: 3)
    }

    private var label: String {
        switch model.status {
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .agentThinking: "Agent thinking"
        case .yourTurn: "Your turn"
        }
    }

    private var dot: Color {
        if model.aneCompileInProgress { return Color(nsColor: .systemOrange) }
        switch model.status {
        case .listening: return Color(nsColor: .systemRed)
        case .transcribing: return Color(nsColor: .systemOrange)
        case .agentThinking: return Color.accentColor
        case .yourTurn: return Color(nsColor: .systemGreen)
        }
    }
}

/// Brain-dump: press to start, press to stop. Generate stays a separate press.
struct SpeakToggle: View {
    var model: WindowModel

    var body: some View {
        Button {
            model.toggleListening()
        } label: {
            Label(model.status == .listening ? "Stop" : "Speak", systemImage: "mic.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!model.canStartListening && model.status != .listening)
        .tint(model.status == .listening ? Color(nsColor: .systemRed) : nil)
        .accessibilityLabel(model.status == .listening ? "Stop listening" : "Start listening")
    }
}

/// Chat: hold to talk. Send stays a separate press. The take replaces the field when it lands.
///
/// Visuals follow the press, not `Session.Status`. Painting from status rebuilds this view
/// the moment listening lands, which cancels the gesture and stops the take.
struct SpeakHold: View {
    var model: WindowModel
    @GestureState private var holding = false

    var body: some View {
        Label("Speak", systemImage: "mic.fill")
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(holding
                        ? Color(nsColor: .systemRed).opacity(0.18)
                        : Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        holding
                            ? Color(nsColor: .systemRed)
                            : Color(nsColor: .separatorColor)
                    )
            }
            .opacity(model.canStartListening || holding ? 1 : 0.4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($holding) { _, state, _ in state = true }
            )
            .onChange(of: holding) { _, down in
                model.holdToTalk(down)
            }
            .accessibilityLabel("Hold to talk")
            .accessibilityAddTraits(.isButton)
    }
}
