import SwiftUI
import Fakthis

/// Project terms, on the Project: the canonical spellings of this Project's domain nouns,
/// handwritten, empty by default and shipped with none (§5).
///
/// They do two jobs from one list. They go into the system prompt as Context, next to the
/// Catalog, so the agent spells the house nouns the way the house does. And they are the head of
/// the transcriber's boost list, so those are the words a take is biased to hear. **Empty means
/// biasing is off** — not that biasing runs on nothing.
///
/// One term per line, because the list is handwritten and a line is how a term is written down.
/// `Session` decides what counts as a term, so a blank line is not one; this is a form, not the
/// Draft, so Cancel means what it says and nothing is committed until Save.
struct ProjectTerms: View {
    var model: WindowModel
    var close: () -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Project terms — \(model.projectKey)")
                    .font(.system(size: 15, weight: .semibold))
                Text(
                    "Canonical spellings of this Project's nouns, one per line. They are "
                        + "Context for the agent and the words the transcriber is biased to "
                        + "hear. An empty list turns biasing off."
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $text)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 260)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }

            Text("Write \u{201C}term / alias\u{201D} to add a spelling the transcriber should also hear.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            HStack {
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    Task {
                        await model.perform(
                            .editProjectTerms(text.components(separatedBy: .newlines))
                        )
                        close()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.working)
            }
        }
        .frame(width: 420)
        .padding(22)
        .task { text = model.projectTerms.joined(separator: "\n") }
    }
}
