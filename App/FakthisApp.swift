import SwiftUI
import AppKit
import Fakthis

/// One window. Before Generate it is the front door; Generate reveals the workbench. They are not
/// two windows and not two modes — they are the same window before and after there is a Draft.
struct FakthisWindow: View {
    @State private var model: WindowModel?
    @State private var failure: String?

    var body: some View {
        Group {
            // A throw here is not an unreachable Jira or a failed Generate — `Session` keeps the
            // Draft through those (§15). It means Fakthis cannot read its own files, and there is
            // nothing to render.
            if let broken = failure ?? model?.failure {
                ContentUnavailableView(
                    "Fakthis could not open",
                    systemImage: "exclamationmark.triangle",
                    description: Text(broken)
                )
            } else if let model, model.hasProject {
                if let draft = model.draft {
                    Workbench(model: model, draft: draft)
                } else {
                    FrontDoor(model: model)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard model == nil else { return }
            let session = FixtureProject.session()
            do {
                _ = try await FixtureProject.open(session)
            } catch {
                failure = String(describing: error)
                return
            }
            let model = WindowModel(session: session)
            await model.open()
            self.model = model
        }
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
