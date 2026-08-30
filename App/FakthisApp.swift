import SwiftUI
import AppKit
import Fakthis

/// One window, and everything before it. First launch collects the credentials, the Project list
/// opens a Project, and from there the window is the front door until Generate reveals the
/// workbench. They are not separate windows and not modes — they are what one window is with
/// nothing set up, with nothing open, and with a Draft in hand.
struct FakthisWindow: View {
    @State private var model: WindowModel?

    var body: some View {
        Group {
            // A throw here is not an unreachable Jira or a failed Generate — `Session` keeps the
            // Draft through those (§15). It means Fakthis cannot read its own files or its own
            // Keychain items, and there is nothing to render.
            if let broken = model?.failure {
                ContentUnavailableView(
                    "Fakthis could not open",
                    systemImage: "exclamationmark.triangle",
                    description: Text(broken)
                )
            } else if let model {
                surface(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard model == nil else { return }
            let model = WindowModel(session: Live.open())
            await model.open()
            self.model = model
        }
    }

    /// The order is what has to exist before the next thing can: credentials before a Project,
    /// a Project before a Draft. Adding a Project is also reachable from a Project that is
    /// already open, and there the list is a sheet the front door raises rather than a surface
    /// that replaces it.
    @ViewBuilder
    private func surface(_ model: WindowModel) -> some View {
        Group {
            if model.settings == nil {
                Setup(model: model)
            } else if !model.hasProject {
                ProjectList(model: model)
            } else if let draft = model.draft {
                Workbench(model: model, draft: draft)
            } else {
                FrontDoor(model: model)
            }
        }
        .task { await model.waitForANECompile() }
    }
}

/// `swift run` launches Fakthis without the activation an `.app` bundle would get, so the
/// window asks for it once it exists.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
    }
}

struct FakthisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Fakthis") {
            // The narrowest and shortest the window goes. Width: rail, conversation and the
            // dividers leave the Draft 636pt of measure, well clear of `WindowShape.draftFloor`,
            // so the resting three-column shape holds all the way down and only the signal panel
            // has to trade for its width. Height: enough for the Draft's fixed footer, the
            // rewrite diff above it and a description worth reading between them.
            FakthisWindow().frame(minWidth: 1240, minHeight: 800)
        }
        .defaultSize(width: 1340, height: 880)
    }
}

@main
struct Entry {
    static func main() {
        NSApplication.shared.setActivationPolicy(.regular)
        FakthisApp.main()
    }
}
