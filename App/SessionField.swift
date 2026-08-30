import SwiftUI
import Fakthis

/// The one field `Session` owns, wherever the window draws it: the brain-dump on the front door,
/// the chat composer in the conversation column. There is only ever one of them, because there is
/// only ever one field behind it.
///
/// Every edit goes straight in as an intent, and a field `Session` changed for its own reasons —
/// a take the transcriber appended, or a press that spent what was typed — is adopted back out.
/// So the words the PM reads are the words Generate and Send are given, and the window keeps no
/// second copy of them.
struct SessionField<Content: View>: View {
    var model: WindowModel
    @ViewBuilder var content: (Binding<String>) -> Content

    @State private var text = ""
    @State private var pushesInFlight = 0

    var body: some View {
        content($text)
            .onAppear { text = model.field }
            .onChange(of: text) { _, typed in
                pushesInFlight += 1
                Task {
                    await model.type(typed)
                    pushesInFlight -= 1
                }
            }
            .onChange(of: model.field) { _, field in
                // Only while the field is quiet. A state that arrived mid-keystroke is behind
                // what has been typed, and adopting it would undo the typing.
                guard pushesInFlight == 0, field != text else { return }
                text = field
            }
    }
}
