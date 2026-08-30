import SwiftUI
import AppKit
import Fakthis

/// The field the brain-dump is spoken or typed into.
///
/// It is a text view because it has to be one, and a text view already answers drops and pastes
/// on its own: dropping a screenshot on it writes the file's path into the dump, which is neither
/// what the PM meant nor what Material is. So the field takes those two gestures first, and only
/// hands them back to the text view when what arrived is words — pasting words into a brain-dump
/// is typing, not attaching.
struct BrainDumpField: NSViewRepresentable {
    @Binding var text: String
    var attach: ([Fakthis.Material]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let field = ComposerTextView(frame: .zero)
        field.delegate = context.coordinator
        field.attach = attach
        field.isRichText = false
        field.font = .systemFont(ofSize: 13.5)
        field.drawsBackground = false
        field.textContainerInset = NSSize(width: 6, height: 8)
        field.isAutomaticQuoteSubstitutionEnabled = false
        field.isAutomaticDashSubstitutionEnabled = false
        field.isVerticallyResizable = true
        field.autoresizingMask = [.width]
        field.minSize = .zero
        field.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        field.textContainer?.widthTracksTextView = true
        // A plain text view answers for the file paths it can spell out, but not for images.
        field.registerForDraggedTypes(field.registeredDraggedTypes + [.fileURL, .png, .tiff])
        field.string = text

        let scroll = NSScrollView()
        scroll.documentView = field
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let field = scroll.documentView as? ComposerTextView else { return }
        field.attach = attach
        PlainTextView.adopt(text, into: field)
    }

    func makeCoordinator() -> TypingCoordinator { TypingCoordinator(text: $text) }
}

/// Takes a drop or a paste that carries Material, and leaves everything else to the text view.
final class ComposerTextView: NSTextView {
    var attach: (([Fakthis.Material]) -> Void)?

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let material = MaterialIntake.material(from: sender.draggingPasteboard)
        guard !material.isEmpty else { return super.performDragOperation(sender) }
        attach?(material)
        return true
    }

    override func paste(_ sender: Any?) {
        let material = MaterialIntake.material(from: .general)
        guard !material.isEmpty else { return super.paste(sender) }
        attach?(material)
    }
}
