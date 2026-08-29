// THROWAWAY PROTOTYPE. Entry point.
//
//   swift run FakthisPrototype            → the window, variant switcher along the bottom
//   swift run FakthisPrototype --shoot    → renders every variant × scene into Prototype/Shots
//
// The switcher follows the prototype skill: previous / label / next, plus the scene buttons
// that drive the Session into a state worth looking at. It is obviously not part of the design.

import SwiftUI
import AppKit
import Fakthis

enum Variant: String, CaseIterable {
    case a, b, c

    var key: String { rawValue.uppercased() }

    var name: String {
        switch self {
        case .a: "Workbench — one window, two panes"
        case .b: "Desk — separate windows, one scroll"
        case .c: "Rail — one window, three columns (2nd pass)"
        }
    }
}

struct Scene: Identifiable {
    var id: String
    var label: String
    var run: @MainActor (Store) async -> Void
}

@MainActor let scenes: [Scene] = [
    Scene(id: "1-braindump", label: "Brain-dump") { await $0.sceneBrainDump() },
    Scene(id: "2-draft", label: "Draft") { await $0.sceneDraft() },
    Scene(id: "3-signals", label: "All signals") { await $0.sceneAllSignals() },
    Scene(id: "4-batch", label: "Batch") { await $0.sceneBatch() },
    Scene(id: "5-rewrite", label: "Rewrite") { await $0.sceneRewrite() },
]

struct Shell: View {
    @Bindable var store: Store
    var variant: Variant
    var style: PreGenerate = .fieldCentre

    var body: some View {
        switch variant {
        case .a: VariantA(store: store)
        case .b: VariantB(store: store)
        case .c: VariantC(store: store, style: style)
        }
    }
}

// MARK: - Running window

struct Root: View {
    @State private var store = Store()
    @State private var variant = Variant.a
    @State private var style = PreGenerate.fieldCentre
    @State private var ready = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if ready {
                Shell(store: store, variant: variant, style: style)
            } else {
                Color(white: 0.95)
            }
            switcher
        }
        .task {
            await store.bootstrap()
            ready = true
        }
    }

    private var switcher: some View {
        HStack(spacing: 10) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut("[", modifiers: .command)
            VStack(spacing: 0) {
                Text("\(variant.key) · \(variant.name)")
                    .font(.system(size: 11, weight: .semibold))
                Text("⌘[ ⌘] to switch variant")
                    .font(.system(size: 8.5)).opacity(0.6)
            }
            .frame(width: 250)
            Button { cycle(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut("]", modifiers: .command)
            if variant == .c {
                Divider().frame(height: 18)
                ForEach(Array(PreGenerate.allCases.enumerated()), id: \.element) { i, option in
                    Button(option.label) { style = option }
                        .font(.system(size: 10.5,
                                      weight: option == style ? .bold : .regular))
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
            Divider().frame(height: 18)
            ForEach(scenes) { scene in
                Button(scene.label) {
                    Task {
                        let fresh = Store()
                        await fresh.bootstrap()
                        await scene.run(fresh)
                        store = fresh
                    }
                }
                .font(.system(size: 10.5))
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.black.opacity(0.86))
        .clipShape(Capsule())
        .shadow(radius: 12, y: 3)
        .padding(.bottom, 12)
    }

    private func cycle(_ step: Int) {
        let all = Variant.allCases
        let index = (all.firstIndex(of: variant)! + step + all.count) % all.count
        variant = all[index]
    }
}

struct PrototypeApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup("Fakthis — UI shell prototype") {
            Root()
                .frame(minWidth: 1240, minHeight: 800)
        }
        .defaultSize(width: 1340, height: 880)
    }
}

// MARK: - Shooting

@MainActor
enum Shooter {
    static let size = CGSize(width: 1340, height: 880)

    static func run(into folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for variant in Variant.allCases {
            for scene in scenes {
                let store = Store()
                await store.bootstrap()
                await scene.run(store)
                let view = Shell(store: store, variant: variant)
                    .environment(\.shooting, true)
                    .environment(\.colorScheme, .light)
                    .frame(width: size.width, height: size.height)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    print("failed \(variant.key) \(scene.id)")
                    continue
                }
                let file = folder
                    .appending(component: "\(variant.rawValue)-\(scene.id).png")
                try png.write(to: file)
                print("wrote \(file.lastPathComponent)")
            }
        }
    }
}

/// Second pass. Shots/ stays frozen as the first-pass primary source that FINDINGS.md cites;
/// the second pass writes to Shots2/ so neither invalidates the other.
@MainActor
enum SecondPass {
    static func run(into folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // The pre-Generate question: three styles, same scene.
        for style in PreGenerate.allCases {
            let store = Store()
            await store.bootstrap()
            await store.sceneBrainDump()
            try shoot(
                Shell(store: store, variant: .c, style: style),
                to: folder.appending(component: "c2-1-braindump-\(style.rawValue).png")
            )
        }

        // The two fixes. Post-Generate the styles are identical, so shoot these once.
        for scene in scenes where scene.id != "1-braindump" {
            let store = Store()
            await store.bootstrap()
            await scene.run(store)
            try shoot(
                Shell(store: store, variant: .c),
                to: folder.appending(component: "c2-\(scene.id).png")
            )
        }
    }

    static func shoot(_ view: some View, to file: URL) throws {
        let renderer = ImageRenderer(
            content: view
                .environment(\.shooting, true)
                .environment(\.colorScheme, .light)
                .frame(width: Shooter.size.width, height: Shooter.size.height)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("failed \(file.lastPathComponent)")
            return
        }
        try png.write(to: file)
        print("wrote \(file.lastPathComponent)")
    }
}

@main
struct Entry {
    static func main() async throws {
        if CommandLine.arguments.contains("--shoot2") {
            let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appending(component: "Prototype")
                .appending(component: "Shots2")
            try await SecondPass.run(into: folder)
            return
        }
        if CommandLine.arguments.contains("--shoot") {
            let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appending(component: "Prototype")
                .appending(component: "Shots")
            try await Shooter.run(into: folder)
            return
        }
        NSApplication.shared.setActivationPolicy(.regular)
        PrototypeApp.main()
    }
}
