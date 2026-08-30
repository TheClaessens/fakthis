import Foundation
import Observation
import Fakthis

/// The window's only state. It holds one `Session.State` — the snapshot the actor handed back —
/// and nothing derived from it that outlives a render. There is no second copy of the Draft, and
/// no rule that belongs behind `Session` is repeated here.
///
/// The field's text is `Session`'s too — the brain-dump before Generate and the chat answer
/// after it are the same one field. The window pushes every edit in and reads the field back
/// out, so a take the transcriber appends is on screen for the PM to look at before Generate,
/// which is the whole point of Generate being a separate press.
@MainActor
@Observable
final class WindowModel {
    private(set) var state: Session.State?
    /// True while the window is waiting on `Session` for a press that takes a round trip — a
    /// Generate, a reshape, a Submit and the upload that follows it.
    private(set) var working = false
    /// Set when a Submit came back without a Ticket. §15: an unreachable Jira leaves the Draft
    /// exactly as it was and the PM retries — but a press that does nothing at all is worse than
    /// the failure, so the window says it.
    private(set) var submitRefused = false
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
        submitRefused = false
        await run { try await $0.perform(intent) }
    }

    /// A keystroke in the field, whichever surface is drawing it. Not named for the brain-dump:
    /// a later chat answer is not one (`CONTEXT.md`), and it goes into the same field. The
    /// intent behind it still carries the old name — renaming it would edit `Prototype/`, which
    /// stands until #40.
    func type(_ text: String) async {
        await perform(.typeBrainDump(text))
    }

    /// Generate is a separate press. The field is already `Session`'s, so this commits nothing —
    /// it only asks for a Draft.
    func generate() async {
        await whileWorking { await perform(.generate) }
    }

    /// Submit creates the Jira issue immediately — no queue, no approval step — and the same
    /// press carries the media upload that follows it, which is why this is the one press the
    /// window waits on.
    func submit() async {
        await whileWorking { await perform(.submit) }
        submitRefused = submitted == nil
    }

    /// A chat answer, sent by its own press. Like Generate it commits nothing — the composer is
    /// already `Session`'s field — it only asks for the Draft to be revised from what the field
    /// holds, and `Session` spends the field doing it.
    func send() async {
        await whileWorking { await perform(.send) }
    }

    /// Reshaping the Draft against another template is a round trip to the agent, so it waits
    /// the same way Generate does.
    func changeTicketType(_ ticketType: TicketType) async {
        await whileWorking { await perform(.changeTicketType(ticketType)) }
    }

    func retryUploads() async {
        await whileWorking { await perform(.retryUploads) }
    }

    private func whileWorking(_ body: () async -> Void) async {
        working = true
        defer { working = false }
        await body()
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
    var submitted: SubmittedTicket? { state?.submitted }
    /// The Draft stops being an editor the moment the Jira issue exists (§4). `Session` owns
    /// that rule; the window reads its answer rather than deriving one from the key.
    var editable: Bool { submitted == nil }
    /// The media Jira will actually be sent. A file Jira refused at attach time is kept with the
    /// Draft but never uploaded (§7), so counting it here would make the upload step say a file
    /// reached the Ticket that never did.
    var media: [AttachedMaterial] { material.filter { $0.isMedia && !$0.blockedFromUpload } }
    var mediaBlockedFromUpload: [String] {
        material.filter { $0.isMedia && $0.blockedFromUpload }.map(\.filename)
    }
    /// A Batch is Submitted and finished as one, so a single Draft inside it cannot be the thing
    /// that starts the next one. `Session` refuses `.newDraft` there; the window does not offer
    /// it rather than offering a press that does nothing.
    var canStartANewDraft: Bool { submitted != nil && failedUploads.isEmpty && state?.batch == nil }
    var failedUploads: [String] { state?.failedUploads ?? [] }
    var field: String { state?.field ?? "" }
    /// The chat, in the order it was said. `Session` has always written it to the Draft folder;
    /// the window renders what it reads back and keeps no turns of its own, which is why the
    /// conversation survives a restart the same way the Draft does.
    var transcript: [TranscriptLine] { state?.transcript ?? [] }
    var material: [AttachedMaterial] { state?.material ?? [] }
    var projectKey: String { state?.project?.key ?? "" }
    var hasProject: Bool { state?.project != nil }
}
