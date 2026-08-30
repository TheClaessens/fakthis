import SwiftUI
import AppKit

/// The description while it is being typed: a real text view.
///
/// A SwiftUI `TextEditor` here was a field the window re-rendered rather than a text view. It did
/// not take the caret when the PM clicked into it — the keystrokes went to whatever field
/// happened to hold focus, which is the short label — and once it had the caret it could not
/// scroll to follow one, because it is a text view with its own scrolling switched off inside the
/// Draft column's scroll. Typing is the one thing a Draft is for, so the description is an
/// `NSTextView`: it takes the caret when it appears, places it where the mouse goes, keeps undo
/// and selection and spellcheck, scrolls the column to the caret, and lays out the text itself
/// instead of being rebuilt from a string on every keystroke.
///
/// The string still goes to `Session` on every keystroke through `InPlaceEdit`, so the window
/// keeps no second copy of the Draft. What changed is who draws the words.
struct DescriptionField: NSViewRepresentable {
    @Binding var text: String
    /// Focus left, or Escape was pressed: the PM has stopped typing.
    var finished: () -> Void

    func makeNSView(context: Context) -> GrowingTextView {
        let field = GrowingTextView(frame: .zero)
        field.delegate = context.coordinator
        field.finished = finished
        PlainTextView.configure(
            field,
            font: .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        )
        field.textContainerInset = NSSize(width: 0, height: 2)
        field.string = text
        // The click that opened the editor landed on the rendered Markdown, so the text view is
        // not yet in the window when this runs. Asking on the next pass is what makes the caret
        // arrive at all — without it the keystrokes go to the first field above. The pointer has
        // not moved by then, so the caret lands under it rather than at one end of the text.
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.placeCaretUnderPointer()
        }
        return field
    }

    func updateNSView(_ field: GrowingTextView, context: Context) {
        field.finished = finished
        context.coordinator.finished = finished
        PlainTextView.adopt(text, into: field)
    }

    func makeCoordinator() -> TypingCoordinator {
        TypingCoordinator(text: $text, finished: finished)
    }
}

/// A text view that is as tall as its text, so the Draft column's scroll is the only scroll on
/// the description. Two scrollers over one body of text is the thing that reads as a field in a
/// page rather than as a page.
final class GrowingTextView: NSTextView {
    var finished: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight)
    }

    override func didChangeText() {
        super.didChangeText()
        syncHeight()
    }

    /// The column can change width — the signal panel opens, the conversation collapses — and a
    /// rewrap is a new height.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncHeight()
    }

    override func cancelOperation(_ sender: Any?) {
        finished?()
    }

    /// Where the caret goes when the editor opens: under the mouse, which is still sitting on the
    /// word the PM clicked. The text reflows when it stops being rendered Markdown, so this is
    /// the same promise any editor makes — the caret is where the pointer is — rather than an
    /// attempt to find the clicked word in a string that no longer looks like what was clicked.
    func placeCaretUnderPointer() {
        guard let window else { return }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = convert(inWindow, from: nil)
        guard bounds.contains(point) else { return }
        let index = characterIndexForInsertion(at: point)
        setSelectedRange(NSRange(location: index, length: 0))
    }

    private var lastHeight: CGFloat = 0

    private var measuredHeight: CGFloat {
        guard let container = textContainer, let manager = layoutManager else { return 0 }
        manager.ensureLayout(for: container)
        return manager.usedRect(for: container).height + textContainerInset.height * 2
    }

    /// Guarded, because invalidating from `setFrameSize` on every pass is a layout loop.
    private func syncHeight() {
        let height = measuredHeight
        guard abs(height - lastHeight) > 0.5 else { return }
        lastHeight = height
        invalidateIntrinsicContentSize()
    }
}
