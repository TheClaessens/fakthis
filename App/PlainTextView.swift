import SwiftUI
import AppKit

/// What the window's two text views have in common.
///
/// The brain-dump on the front door and the description in the Draft are the same object twice:
/// a plain text view the PM types into, whose every keystroke goes straight to `Session` so the
/// window keeps no second copy of what it is showing. They differ in what they are inside — one
/// scrolls itself and answers drops, the other grows to its text inside the Draft's scroll — and
/// in nothing else, so the setup and the delegate live here rather than twice.
@MainActor
enum PlainTextView {
    /// Plain text, not a document. Both fields hold Markdown the PM typed: a smart quote or an em
    /// dash substituted into it is a character they did not type and Submit would write.
    static func configure(_ field: NSTextView, font: NSFont) {
        field.isRichText = false
        field.allowsUndo = true
        field.font = font
        field.drawsBackground = false
        field.isAutomaticQuoteSubstitutionEnabled = false
        field.isAutomaticDashSubstitutionEnabled = false
        field.isVerticallyResizable = true
        field.isHorizontallyResizable = false
        field.autoresizingMask = [.width]
        field.minSize = .zero
        field.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        field.textContainer?.widthTracksTextView = true
    }

    /// Only when `Session` changed the field out from under the text view — a take the
    /// transcriber appended, a Draft the agent rewrote. Writing on every pass would fight the
    /// typing and drop the selection.
    static func adopt(_ text: String, into field: NSTextView) {
        if field.string != text { field.string = text }
    }
}

/// Every keystroke out to the binding, which is what makes the field `Session`'s rather than the
/// window's, and the end of typing out to whoever asked for it.
@MainActor
final class TypingCoordinator: NSObject, NSTextViewDelegate {
    private let text: Binding<String>
    /// The description's editor closes on this. The brain-dump has nowhere to close to, so it
    /// leaves it nil.
    var finished: (() -> Void)?

    init(text: Binding<String>, finished: (() -> Void)? = nil) {
        self.text = text
        self.finished = finished
    }

    func textDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextView else { return }
        text.wrappedValue = field.string
    }

    func textDidEndEditing(_ notification: Notification) {
        finished?()
    }
}
