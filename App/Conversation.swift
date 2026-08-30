import SwiftUI
import Fakthis

/// The third column: the chat on screen, a composer, and **Send** as its own press.
///
/// It exists only once a Draft does. Before Generate the window is the front door and this column
/// is not there — not even as a spine, because a spine reading "nothing said yet" is furniture
/// over a surface that cannot be used yet.
///
/// It **collapses to a spine** and expands again, and the Draft column takes the width when it
/// does. Rewrite will open with it collapsed — Update does not require Generate — which is why
/// the collapse is a binding the surface owns rather than a switch hidden in here.
struct ConversationColumn: View {
    var model: WindowModel
    @Binding var collapsed: Bool

    /// The bottom of the transcript, so a new turn scrolls into view instead of arriving below
    /// the fold.
    private let foot = "conversation-foot"

    var body: some View {
        if collapsed {
            spine
        } else {
            column
        }
    }

    // MARK: - Collapsed

    /// The whole spine is the press that brings the column back, so the chevron is a hint rather
    /// than a target you have to hit.
    private var spine: some View {
        VStack(spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Conversation")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(width: 18, height: 110)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .frame(width: 34)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { collapsed = false }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Expand the conversation")
    }

    // MARK: - Expanded

    private var column: some View {
        VStack(spacing: 0) {
            ColumnTitle("Conversation") {
                Button {
                    collapsed = true
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.accessoryBar)
                .accessibilityLabel("Collapse the conversation")
            }
            transcript
            Divider()
            composer
        }
        .frame(width: 340)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// The chat as `Session` recorded it: what the PM said, then the questions the agent asked
    /// back, in order. It is read out of state and survives a restart for the same reason the
    /// Draft does — `Session` writes it to the Draft folder and the window renders what it reads.
    private var transcript: some View {
        ScrollViewReader { scroll in
            ScrollView {
                // No empty state: the column only exists once a Draft does, and the press that
                // made the Draft is already the first thing in the conversation. A line saying
                // nothing has been said is the furniture finding 14 threw out.
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(model.transcript.enumerated()), id: \.offset) { _, line in
                        turn(line)
                    }
                    if model.working {
                        Text("Thinking…")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Color.clear.frame(height: 1).id(foot)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: model.transcript.count) { _, _ in
                withAnimation { scroll.scrollTo(foot, anchor: .bottom) }
            }
            .onAppear { scroll.scrollTo(foot, anchor: .bottom) }
        }
    }

    /// One turn. The agent's turns are its open questions — the only thing it says to the PM;
    /// everything else it produces is the Draft, which the middle column is already showing.
    private func turn(_ line: TranscriptLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.role == .agent ? "Fakthis" : "You")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(line.role == .agent ? Color.accentColor : .secondary)
            Text(line.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    // MARK: - Composer

    /// **Send is a separate press** (§7.4). Typing revises nothing: the composer is `Session`'s
    /// field and the window pushes every keystroke into it, but only this press asks the agent
    /// for a Draft. The press spends the field, so the answer leaves the composer and joins the
    /// conversation above it. Speak on this composer is hold-to-talk; the take replaces the
    /// field, and Send still waits for this press.
    private var composer: some View {
        SessionField(model: model) { text in
            VStack(alignment: .leading, spacing: 0) {
                VoiceStrip(model: model, gesture: "Hold to talk")
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Answer", text: text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .lineLimit(1...6)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        }
                        .disabled(model.working)

                    HStack {
                        SpeakHold(model: model)
                        Spacer()
                        Button {
                            Task { await model.send() }
                        } label: {
                            Label("Send", systemImage: "arrow.up.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!canSend(text.wrappedValue))
                    }
                }
                .padding(12)
            }
        }
    }

    private func canSend(_ text: String) -> Bool {
        !model.working && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
