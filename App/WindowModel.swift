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
    /// Set when a Jira project key came back without a proposal. §15 leaves the app exactly as
    /// it was when Jira does not answer — but, as with Submit, a press that does nothing at all
    /// is worse than the failure, so the window says it.
    private(set) var projectKeyRefused = false
    /// Same shape as `projectKeyRefused`, for a Ticket key that Jira did not answer. A 404, an
    /// epic and another Project's key are `rewriteError` instead — those are refusals with a
    /// reason, not a press that vanished.
    private(set) var pasteKeyRefused = false
    /// Same shape as `submitRefused`, for an Update (or a clobber) that Jira did not answer.
    /// A stale `updated` is not this: that is a warn, and the Draft is still an editor.
    private(set) var updateRefused = false
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
        projectKeyRefused = false
        pasteKeyRefused = false
        updateRefused = false
        await run { try await $0.perform(intent) }
    }

    // MARK: - Setup and the Project list

    /// First launch. Both secrets go to Keychain and the rest to `settings.json`; `Session` is
    /// what splits them, so the window hands over all six and reads back what it kept.
    func saveCredentials(_ settings: Settings, jiraToken: String, modelKey: String) async {
        await whileWorking {
            await perform(
                .saveCredentials(settings, jiraToken: jiraToken, modelKey: modelKey)
            )
        }
    }

    /// A Jira project key. It is a round trip — Fakthis asks the site what issue types the
    /// project has (§3.2) — so it waits, and says so if nothing came back.
    func enterProjectKey(_ key: String) async {
        await whileWorking { await perform(.enterProjectKey(key)) }
        projectKeyRefused = proposedProject == nil
    }

    /// Confirming the mapping creates the Project and takes its first Catalog pull, so this is
    /// the second round trip in adding one.
    func confirmProject(mapping: [TicketType: String]) async {
        await whileWorking { await perform(.confirmProject(mapping: mapping)) }
    }

    /// `Transcriber.compileStatus()` is a question, not a signal, so the setup screen asks it
    /// until the answer changes. It is the one thing in the window that moves without the PM
    /// pressing anything.
    func waitForANECompile() async {
        repeat {
            await open()
            if !aneCompileInProgress { return }
            try? await Task.sleep(for: .milliseconds(400))
        } while !Task.isCancelled && failure == nil
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
        await whileWorking { await self.followStatus { await self.perform(.generate) } }
    }

    /// Brain-dump is a toggle: one press starts the take, the next stops it and the words land
    /// in the field. Chat is hold-to-talk, same two intents, so both gestures enqueue here — a
    /// release that raced the press would hit `stopListening` while status was still `yourTurn`
    /// and leave the take running with nothing to commit it.
    func toggleListening() {
        enqueueVoice { [self] in
            switch status {
            case .listening:
                await self.followStatus { await self.perform(.stopListening) }
            case .yourTurn where canStartListening:
                await self.followStatus { await self.perform(.startListening) }
            default:
                break
            }
        }
    }

    /// Hold is the chat gesture. The visual lives on the control; this only starts and stops so
    /// a rebuild of the strip cannot be what commits the take.
    func holdToTalk(_ down: Bool) {
        enqueueVoice { [self] in
            if down {
                guard canStartListening else { return }
                await self.followStatus { await self.perform(.startListening) }
            } else if status == .listening {
                await self.followStatus { await self.perform(.stopListening) }
            }
        }
    }

    /// Submit creates the Jira issue immediately — no queue, no approval step — and the same
    /// press carries the media upload that follows it, which is why this is the one press the
    /// window waits on. Rewrite never comes through here: a Draft bound to a key Updates.
    func submit() async {
        await whileWorking { await perform(.submit) }
        submitRefused = submitted == nil
    }

    /// Fetch the live Ticket and bind a rewrite Draft to that key. A round trip, so it waits
    /// the way Generate does. The window does not decide what a bad key is — `Session` does.
    func pasteKey(_ key: String) async {
        pasteKeyRefused = false
        await whileWorking { await perform(.pasteKey(key)) }
        pasteKeyRefused = draft == nil && rewriteError == nil
    }

    /// Write title, description and the completeness marker. Watchers are emailed; that fact
    /// sits on the button, not here. A stale `updated` comes back as `rewrite.stale` rather
    /// than a write, so this is not refused — the footer offers Re-fetch.
    func update() async {
        updateRefused = false
        await whileWorking { await perform(.update) }
        updateRefused = rewrite != nil && rewrite?.stale != true
    }

    func refetch() async {
        await whileWorking { await perform(.refetch) }
    }

    /// Proceed anyway after a stale `updated`. The Draft survives either way; this is the
    /// write that clobbers.
    func clobber() async {
        updateRefused = false
        await whileWorking { await perform(.clobber) }
        updateRefused = rewrite != nil
    }

    /// A chat answer, sent by its own press. Like Generate it commits nothing — the composer is
    /// already `Session`'s field — it only asks for the Draft to be revised from what the field
    /// holds, and `Session` spends the field doing it.
    func send() async {
        await whileWorking { await self.followStatus { await self.perform(.send) } }
    }

    /// Reshaping the Draft against another template is a round trip to the agent, so it waits
    /// the same way Generate does.
    func changeTicketType(_ ticketType: TicketType) async {
        await whileWorking {
            await self.followStatus { await self.perform(.changeTicketType(ticketType)) }
        }
    }

    func retryUploads() async {
        await whileWorking { await perform(.retryUploads) }
    }

    /// A Jira key lands in the rewrite loop; a local Draft is focused. Either way it is
    /// `Session`'s landing, and a fetch is a round trip, so this waits the way Generate does.
    func workOnDuplicate() async {
        await whileWorking { await perform(.workOnDuplicate) }
    }

    /// The second pass again, over the description the PM edited. A round trip to the agent, so
    /// it waits the way Generate does — and it is a press, never silent (§7.3).
    func regenerateDefinitionOfDone() async {
        await whileWorking {
            await self.followStatus { await self.perform(.regenerateDefinitionOfDone) }
        }
    }

    private func whileWorking(_ body: () async -> Void) async {
        working = true
        defer { working = false }
        await body()
    }

    /// `perform` returns the snapshot at the end of a wait. The strip has to show transcribing
    /// and agent thinking *during* that wait, so this reads `state()` on the actor while the
    /// intent is still in flight — the same hop `waitForANECompile` already makes, because
    /// `Session` yields at the transcriber and the model.
    private func followStatus(_ body: @escaping () async -> Void) async {
        let poll = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                await self.open()
            }
        }
        await body()
        poll.cancel()
    }

    private var voiceQueue: Task<Void, Never>?

    private func enqueueVoice(_ body: @escaping () async -> Void) {
        voiceQueue = Task { [voiceQueue] in
            await voiceQueue?.value
            await body()
        }
    }

    private func run(_ body: (Session) async throws -> Session.State) async {
        do {
            self.state = try await body(session)
            failure = nil
        } catch {
            failure = String(describing: error)
        }
    }

    // MARK: - What the window reads

    var draft: Draft? { state?.draft }
    var submitted: SubmittedTicket? { state?.submitted }
    /// Present exactly while this Draft is a rewrite: bound to a key, still an editor, and
    /// Update is the write. The window reads it rather than guessing from `draft.key`, because
    /// a leftover create that has a key is an upload queue, not a rewrite.
    var rewrite: Rewrite? { state?.rewrite }
    var rewriteError: String? { state?.rewriteError }
    /// The Draft stops being an editor the moment the Jira issue exists (§4). `Session` owns
    /// that rule; the window reads its answer rather than deriving one from the key.
    var editable: Bool { submitted == nil }
    /// The media Jira will actually be sent. A file Jira refused at attach time is kept with the
    /// Draft but never uploaded (§7), so counting it here would make the upload step say a file
    /// reached the Ticket that never did.
    var media: [AttachedMaterial] { material.filter { $0.isMedia && !$0.blockedFromUpload } }
    /// The structural check, split by the field each warning is about. `Session` does the
    /// splitting — which field a warning belongs to is §9's rule, not a guess the window makes
    /// from the warning's wording.
    var titleWarnings: [StructuralWarning] { structuralWarnings(.title) }
    var descriptionWarnings: [StructuralWarning] { structuralWarnings(.description) }
    /// What rests in the gutter. Assembled behind the actor too, for the same reason.
    var draftSignals: [DraftSignal] { state?.draftSignals ?? [] }
    /// A duplicate while it is an interrupt in the conversation. Continue collapses it to
    /// `duplicateMark`; they are never both set, and neither is a Draft signal.
    var duplicateInterrupt: DuplicateHit? { state?.duplicateInterrupt }
    var duplicateMark: DuplicateHit? { state?.duplicateMark }
    /// Ignorable, cap three, default off as a write. Empty means no UI — not an empty state.
    var related: [RelatedHit] { state?.related ?? [] }
    var offerRegenerateDefinitionOfDone: Bool {
        state?.offerRegenerateDefinitionOfDone ?? false
    }
    /// A Batch is Submitted and finished as one, so a single Draft inside it cannot be the thing
    /// that starts the next one. `Session` refuses `.newDraft` there; the window does not offer
    /// it rather than offering a press that does nothing.
    var canStartANewDraft: Bool { submitted != nil && failedUploads.isEmpty && state?.batch == nil }
    var failedUploads: [String] { state?.failedUploads ?? [] }
    var field: String { state?.field ?? "" }
    /// The phase the strip on the field reads. Four values, never a sound: listening /
    /// transcribing / agent thinking / your turn.
    var status: Session.Status { state?.status ?? .yourTurn }
    /// Speak is offered in `yourTurn` once the transcriber is compiled. Disabled while the
    /// agent is thinking, not while listening — Stop has to stay reachable.
    var canStartListening: Bool {
        hasProject && !aneCompileInProgress && status == .yourTurn && !working
    }
    /// The chat, in the order it was said. `Session` has always written it to the Draft folder;
    /// the window renders what it reads back and keeps no turns of its own, which is why the
    /// conversation survives a restart the same way the Draft does.
    var transcript: [TranscriptLine] { state?.transcript ?? [] }
    var material: [AttachedMaterial] { state?.material ?? [] }
    var projectKey: String { state?.project?.key ?? "" }
    var hasProject: Bool { state?.project != nil }
    var settings: Settings? { state?.settings }
    var aneCompileInProgress: Bool { state?.aneCompileInProgress ?? false }
    /// Every local Project, and the one being added. Both are `Session`'s: which folders count
    /// as Projects, and which Jira issue types a project offers, are answers the window reads.
    var projects: [String] { state?.projects ?? [] }
    var proposedProject: ProposedProject? { state?.proposedProject }
    /// Handwritten canonical spellings on the open Project (§5), empty by default.
    var projectTerms: [String] { state?.project?.terms ?? [] }
    /// The disclosure that text Material goes to the model provider, while it is outstanding.
    /// It has two moments and two homes: on the screen that confirms a Project it is part of
    /// what is being confirmed, and everywhere else it arrives on its own and has to be read.
    /// Never in the Draft UI.
    var textMaterialDisclosure: String? { state?.textMaterialDisclosure }

    private func structuralWarnings(_ field: StructuralWarning.Field) -> [StructuralWarning] {
        (state?.structuralWarnings ?? []).filter { $0.field == field }
    }
}
