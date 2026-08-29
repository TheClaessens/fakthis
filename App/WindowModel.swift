import Foundation
import Observation
import Fakthis

/// The window's only state. It holds one `Session.State` — the snapshot the actor handed back —
/// and nothing derived from it that outlives a render. There is no second copy of the Draft, and
/// no rule that belongs behind `Session` is repeated here.
///
/// The composer's text is `Session`'s too. The window pushes every edit in as `.typeBrainDump`
/// and reads the field back out, so a take the transcriber appends is on screen for the PM to
/// look at before Generate — which is the whole point of Generate being a separate press.
@MainActor
@Observable
final class WindowModel {
    private(set) var state: Session.State?
    private(set) var generating = false
    private(set) var failure: String?

    private let session: Session

    init(session: Session) {
        self.session = session
    }

    /// The window opens on whatever `Session` already has: its Project and, after a restart, the
    /// Draft that was in progress.
    func open() async {
        await run { try await $0.state() }
    }

    func perform(_ intent: Session.Intent) async {
        await run { try await $0.perform(intent) }
    }

    func typeBrainDump(_ text: String) async {
        await perform(.typeBrainDump(text))
    }

    /// Generate is a separate press. The field is already `Session`'s, so this commits nothing —
    /// it only asks for a Draft.
    func generate() async {
        generating = true
        defer { generating = false }
        await perform(.generate)
    }

    private func run(_ body: (Session) async throws -> Session.State) async {
        do {
            state = try await body(session)
            failure = nil
        } catch {
            failure = String(describing: error)
        }
    }

    // MARK: - What the window reads

    var draft: Draft? { state?.draft }
    var field: String { state?.field ?? "" }
    var material: [AttachedMaterial] { state?.material ?? [] }
    var projectKey: String { state?.project?.key ?? "" }
    var hasProject: Bool { state?.project != nil }
}
