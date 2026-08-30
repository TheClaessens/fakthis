import SwiftUI
import Fakthis

/// A Draft field the PM edits in place.
///
/// The window keeps no second copy of the Draft: every keystroke goes to `Session` as an intent
/// and the value is read back out of the next snapshot, so what is on screen and what Submit
/// writes are the same string and cannot drift apart.
///
/// A snapshot that arrives mid-keystroke is behind what has been typed, so it is adopted only
/// while the field is quiet — the same rule the front door's composer follows for a take the
/// transcriber appended.
///
/// One keystroke does not mean one hop to the actor. A `Task` per keystroke would reach `Session`
/// in whatever order the scheduler chose, and an older push landing last would leave the Draft
/// holding a string the screen has already moved past — the exact drift this is here to prevent.
/// So the pushes are a queue of one: whatever was typed last is what goes next, and only one is
/// ever in flight.
struct InPlaceEdit<Content: View>: View {
    var value: String
    var commit: (String) async -> Void
    @ViewBuilder var content: (Binding<String>) -> Content

    @State private var buffer = ""
    @State private var waitingToPush: String?
    @State private var pushing = false

    var body: some View {
        content($buffer)
            .onAppear { buffer = value }
            .onChange(of: buffer) { _, typed in
                guard typed != value else { return }
                push(typed)
            }
            .onChange(of: value) { _, latest in
                guard !pushing, waitingToPush == nil, latest != buffer else { return }
                buffer = latest
            }
    }

    private func push(_ typed: String) {
        waitingToPush = typed
        guard !pushing else { return }
        pushing = true
        Task {
            while let next = waitingToPush {
                waitingToPush = nil
                await commit(next)
            }
            pushing = false
        }
    }
}

/// The Draft's description: read as the agent wrote it, edited where you click.
///
/// Reading is the review (§7.5), so the resting state renders the Markdown — including the
/// open-questions section, at the foot of the description above the horizontal rule, where
/// `Draft` puts it and where Submit writes it.
///
/// Editing binds to the raw description, never to the composed string. The section is made out
/// of the questions the agent asked; typing into a copy of it would bake a stale one into the
/// description and the next compose would sit a second section on top.
struct DescriptionEditor: View {
    var draft: Draft
    var editable: Bool
    var commit: (String) async -> Void
    /// That typing has stopped. `Session` waits for it before offering to regenerate the
    /// Definition of Done: a bar raised on the first character would push the text down under
    /// the cursor while it was still being written.
    var finish: () async -> Void

    @State private var editing = false

    var body: some View {
        if editing && editable {
            VStack(alignment: .leading, spacing: 12) {
                InPlaceEdit(value: draft.description, commit: commit) { text in
                    DescriptionField(text: text, finished: stopEditing)
                }
                openQuestions
            }
        } else {
            MarkdownBlocks(markdown: draft.descriptionWithOpenQuestions)
                .font(.system(size: 12.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { editing = editable }
        }
    }

    /// The last keystroke may still be in flight when focus goes, so this can reach `Session`
    /// before it. That is harmless: `Session` holds the hand-edit as a fact rather than a
    /// moment, so a keystroke landing after the finish is simply the edit the next finish is
    /// about — and answering the offer clears both halves.
    private func stopEditing() {
        editing = false
        Task { await finish() }
    }

    /// The questions stay on screen while the description is being typed, because they are still
    /// on the Draft — they are just not the PM's to type. `Draft` puts the section back at the
    /// foot of the description, above the horizontal rule, the moment reading resumes.
    @ViewBuilder
    private var openQuestions: some View {
        if !draft.openQuestions.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(Draft.openQuestionsPreamble)
                ForEach(Array(draft.openQuestions.enumerated()), id: \.offset) { _, question in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(question).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        }
    }
}
