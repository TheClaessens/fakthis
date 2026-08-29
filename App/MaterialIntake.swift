import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Fakthis

/// The three ways Material arrives: dropped on the composer, pasted onto it, or picked from
/// a
/// file panel. All three end in the same `.attachMaterial` intent — routing, warnings and the
/// upload queue are `Session`'s business, not the window's.
enum MaterialIntake {
    @MainActor static func openPanel() -> [Fakthis.Material] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Attach"
        panel.message = "Attach the raw material that produced this brain-dump."
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap(material(fromFileAt:))
    }

    static func material(fromFileAt url: URL) -> Fakthis.Material? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Fakthis.Material(
            filename: url.lastPathComponent,
            mimeType: mimeType(forExtension: url.pathExtension),
            data: data
        )
    }

    /// A pasted screenshot has pixels and no name, so it is given one. `Session` reads the kind
    /// off the mime type, so that has to be right even when the name is invented.
    @MainActor static func pastedMaterial(from pasteboard: NSPasteboard) -> [Fakthis.Material] {
        // File URLs only. Without the restriction a copied link reads back as an `NSURL` and a
        // plain paste of a web address would be swallowed as Material.
        let files = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !files.isEmpty {
            return files.filter(\.isFileURL).compactMap(material(fromFileAt:))
        }
        guard let image = NSImage(pasteboard: pasteboard),
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return [] }
        return [
            Fakthis.Material(
                filename: "pasted-\(pastedNameStamp()).png",
                mimeType: "image/png",
                data: png
            )
        ]
    }

    private static func mimeType(forExtension pathExtension: String) -> String {
        UTType(filenameExtension: pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }

    private static func pastedNameStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

extension AttachedMaterial {
    var glyph: String {
        if isScreenshot { return "photo" }
        if isVideo { return "film" }
        if isText { return "doc.text" }
        return "questionmark.square.dashed"
    }
}

/// Command-V while the composer is on screen. The field is a text view, and a text view eats
/// the paste without acting on it when the pasteboard holds a screenshot or a file — so the
/// window watches for the key itself and only intervenes when there is Material to take. Words
/// on the pasteboard fall through to the field, because pasting words into a brain-dump is
/// typing, not attaching.
@MainActor
final class MaterialPasteMonitor {
    private var monitor: Any?

    func start(attach: @escaping ([Fakthis.Material]) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers == "v"
            else { return event }
            let pasted = MaterialIntake.pastedMaterial(from: .general)
            guard !pasted.isEmpty else { return event }
            attach(pasted)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Drop and paste, on whatever the composer is. Both hand `Session` the same intent.
struct MaterialIntakeModifier: ViewModifier {
    var attach: ([Fakthis.Material]) -> Void
    @State private var targeted = false
    @State private var paste = MaterialPasteMonitor()

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                let attached = urls.compactMap(MaterialIntake.material(fromFileAt:))
                guard !attached.isEmpty else { return false }
                attach(attached)
                return true
            } isTargeted: { targeted = $0 }
            .onAppear { paste.start(attach: attach) }
            .onDisappear { paste.stop() }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
    }
}

extension View {
    func materialIntake(attach: @escaping ([Fakthis.Material]) -> Void) -> some View {
        modifier(MaterialIntakeModifier(attach: attach))
    }
}
