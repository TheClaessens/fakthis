// THROWAWAY PROTOTYPE. One store, three variants read it. Everything the real Session owns
// goes through `session`; everything marked FAKED is held here because State does not carry it
// yet (Batch #27, Rewrite #26, voice phase, duplicate hit, catalog-refresh failure).

import Foundation
import Observation
import Fakthis

enum Surface: String, CaseIterable, Hashable {
    case create, batch, rewrite

    var label: String {
        switch self {
        case .create: "Create"
        case .batch: "Batch"
        case .rewrite: "Rewrite"
        }
    }
}

enum VoicePhase: Hashable {
    case idle, listening, transcribing, thinking, yourTurn

    var label: String {
        switch self {
        case .idle: "Ready"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .thinking: "Agent thinking"
        case .yourTurn: "Your turn"
        }
    }
}

enum SignalKind: Hashable {
    case completeness, structural, material, catalog, duplicate, uploads

    var title: String {
        switch self {
        case .completeness: "Open questions"
        case .structural: "Structural check"
        case .material: "Material"
        case .catalog: "Catalog"
        case .duplicate: "Possible duplicate"
        case .uploads: "Uploads"
        }
    }

    var glyph: String {
        switch self {
        case .completeness: "questionmark.circle"
        case .structural: "ruler"
        case .material: "paperclip"
        case .catalog: "arrow.triangle.2.circlepath"
        case .duplicate: "doc.on.doc"
        case .uploads: "arrow.up.circle"
        }
    }
}

struct SignalAction: Identifiable, Hashable {
    let id = UUID()
    var label: String
}

struct Signal: Identifiable, Hashable {
    let id = UUID()
    var kind: SignalKind
    var text: String
    var actions: [SignalAction] = []
}

@MainActor
@Observable
final class Store {
    var surface: Surface = .create

    // Session.State, unpacked. State's memberwise init is internal to Fakthis, so the prototype
    // mirrors the fields it renders rather than holding a State it cannot construct.
    var draft: Draft?
    var catalog = Catalog()
    var aneCompileInProgress = false
    var proposedProject: ProposedProject?
    var materialWarnings: [String] = []
    var failedUploads: [String] = []
    var structuralWarnings: [String] = []

    // Editable mirror of the Draft. Session has no edit intent, so hand-edits are
    // prototype-local. FAKED IN THE PROTOTYPE LAYER.
    var title = ""
    var shortLabel = ""
    var body = ""
    var dodBullets: [String] = []
    var descriptionWasHandEdited = false

    var field = ""
    var chat: [ChatTurn] = []
    var material: [MaterialRow] = []

    var voice: VoicePhase = .idle
    var duplicateDismissed = false
    var catalogRefreshFailed = false
    var relatedTicked: Set<String> = []

    // §11 Batch — FAKED.
    var batchName = Fixtures.batchName
    var batchDrafts: [BatchDraft] = []
    var batchFocus = 0
    var batchChainCleared = false

    // §12 Rewrite — FAKED.
    var rewriteKey = ""
    var rewriteFetched = false
    var rewriteStale = true
    var rewriteDiffOpen = false

    private let session: Session
    private let jira = FakeJira()
    private let model = ScriptedModel(
        reply: Fixtures.storyReply,
        definitionOfDone: Fixtures.storyDefinitionOfDone
    )

    init() {
        let root = FileManager.default.temporaryDirectory
            .appending(component: "fakthis-prototype-\(UUID().uuidString)")
        session = Session(
            applicationSupport: root,
            model: model,
            jira: jira,
            transcriber: FakeTranscriber(compileFinished: true),
            secrets: FakeSecrets()
        )
    }

    // MARK: - Bootstrap

    /// Walks the real Session up to "a Project exists", which the window is allowed to assume.
    func bootstrap() async {
        await jira.seed(
            epics: Fixtures.epics,
            rows: Fixtures.rows,
            componentNames: ["checkout", "pricing", "mobile-web"],
            issueTypes: Fixtures.issueTypes
        )
        await apply(
            .saveCredentials(
                Settings(
                    site: "faktion.atlassian.net",
                    email: "pm@faktion.com",
                    provider: "anthropic",
                    modelId: "claude-opus-5"
                ),
                jiraToken: "token",
                modelKey: "key"
            )
        )
        await apply(.enterProjectKey("FAK"))
        if let proposed = proposedProject {
            await apply(.confirmProject(mapping: proposed.mapping))
        }
        material = Fixtures.material
        batchDrafts = Fixtures.batchDrafts
        field = Fixtures.brainDump
        await apply(.typeBrainDump(Fixtures.brainDump))
        voice = .idle
    }

    // MARK: - Scenes (drive the prototype into a state worth looking at)

    func sceneBrainDump() async {
        voice = .listening
    }

    func sceneDraft() async {
        await generate()
        chat = Fixtures.chat
        field = ""
        voice = .yourTurn
    }

    /// Every warn-not-block signal lit at once, so their placement can be judged together.
    func sceneAllSignals() async {
        await sceneDraft()
        descriptionWasHandEdited = true
        catalogRefreshFailed = true
        materialWarnings = [
            "repro-mobile-safari.mov is 84 MB, over this site's 10 MB attachment limit."
        ]
        failedUploads = ["checkout-stale-total.png"]
        // Force a structural warning by hand-editing the title off the Story convention.
        title = "Checkout total is stale on mobile"
        body += "\n\n## Technical Notes\n\nProbably the pricing call."
        pushEditsIntoStructuralCheck()
    }

    func sceneBatch() async {
        await sceneDraft()
        surface = .batch
        materialWarnings = [
            "repro-mobile-safari.mov is 84 MB, over this site's 10 MB attachment limit."
        ]
    }

    func sceneRewrite() async {
        await sceneDraft()
        surface = .rewrite
        rewriteKey = Fixtures.rewriteKey
        rewriteFetched = true
        rewriteDiffOpen = true
        title = "As a shopper I want the checkout total to match my current basket "
            + "so that I never pay against a stale figure"
        shortLabel = "Stale checkout total"
        body = Fixtures.rewriteProposedBody
        chat = []
        voice = .yourTurn
    }

    // MARK: - Intents

    func apply(_ intent: Session.Intent) async {
        guard let next = try? await session.perform(intent) else { return }
        catalog = next.catalog
        aneCompileInProgress = next.aneCompileInProgress
        proposedProject = next.proposedProject
        materialWarnings = next.materialWarnings
        failedUploads = next.failedUploads
        structuralWarnings = next.structuralWarnings
        if let draft = next.draft {
            self.draft = draft
            mirror(draft)
        }
    }

    func generate() async {
        voice = .thinking
        await apply(.typeBrainDump(field))
        await apply(.generate)
        voice = .yourTurn
    }

    func send() async {
        guard !field.isEmpty else { return }
        chat.append(ChatTurn(role: .pm, text: field))
        voice = .thinking
        await apply(.typeBrainDump(field))
        await apply(.send)
        field = ""
        voice = .yourTurn
    }

    func changeTicketType(_ type: TicketType) async {
        await apply(.changeTicketType(type))
    }

    func submit() async {
        await apply(.submit)
    }

    func regenerateDefinitionOfDone() async {
        dodBullets = Fixtures.storyDefinitionOfDone
        descriptionWasHandEdited = false
    }

    private func mirror(_ draft: Draft) {
        title = draft.title
        shortLabel = draft.shortLabel
        let parts = draft.description.components(separatedBy: "\n\n---\n\n")
        body = parts.first ?? draft.description
        dodBullets = (parts.count > 1 ? parts[1] : "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)) }
    }

    /// Re-runs the real structural check over the hand-edited Draft by pushing the edits back
    /// through Session's own snapshot path.
    func pushEditsIntoStructuralCheck() {
        guard var edited = draft else { return }
        edited.title = title
        edited.description = recomposedDescription
        draft = edited
        structuralWarnings = warnings(for: edited)
    }

    var recomposedDescription: String {
        let bullets = dodBullets.map { "- \($0)" }.joined(separator: "\n")
        return "\(body)\n\n---\n\n**Definition of Done:**\n\n\(bullets)"
    }

    // MARK: - Derived

    var ticketType: TicketType { draft?.ticketType ?? .story }
    var openQuestions: [String] { draft?.openQuestions ?? [] }
    var hasDraft: Bool { draft != nil }

    var duplicateHit: CatalogRow? {
        guard !duplicateDismissed, hasDraft else { return nil }
        return catalog.rows.first {
            $0.shortLabel == shortLabel && $0.key.value != rewriteKey
        }
    }

    var related: [CatalogRow] {
        guard hasDraft else { return [] }
        return catalog.rows
            .filter { $0.shortLabel != shortLabel }
            .prefix(3)
            .map { $0 }
    }

    var epicName: String {
        catalog.epics.first { $0.key.value == "FAK-100" }
            .map { "\($0.key.value) \($0.name)" } ?? "No epic"
    }

    /// The six warn-not-block signals, in one list. Every variant renders this same array —
    /// the variants differ only in where it goes.
    var signals: [Signal] {
        var out: [Signal] = []
        if !openQuestions.isEmpty {
            out.append(
                Signal(
                    kind: .completeness,
                    text: "\(openQuestions.count) unanswered. Submitting now adds the "
                        + "`fakthis-open-questions` label and lists them in the description.",
                    actions: [SignalAction(label: "Show questions")]
                )
            )
        }
        for warning in structuralWarnings {
            out.append(Signal(kind: .structural, text: warning))
        }
        for warning in materialWarnings {
            out.append(
                Signal(
                    kind: .material,
                    text: warning + " It stays on the Draft and is skipped at Submit.",
                    actions: [SignalAction(label: "Remove file")]
                )
            )
        }
        if catalogRefreshFailed {
            out.append(
                Signal(
                    kind: .catalog,
                    text: "Refresh failed — Jira unreachable. Using the snapshot from 14:02.",
                    actions: [SignalAction(label: "Retry")]
                )
            )
        }
        if let hit = duplicateHit {
            out.append(
                Signal(
                    kind: .duplicate,
                    text: "This looks like \(hit.key.value) — \(hit.shortLabel ?? hit.title).",
                    actions: [
                        SignalAction(label: "Work on \(hit.key.value)"),
                        SignalAction(label: "Continue"),
                    ]
                )
            )
        }
        if !failedUploads.isEmpty {
            out.append(
                Signal(
                    kind: .uploads,
                    text: "\(failedUploads.count) file could not upload: "
                        + failedUploads.joined(separator: ", "),
                    actions: [SignalAction(label: "Retry"), SignalAction(label: "Skip")]
                )
            )
        }
        return out
    }
}

/// A copy of Session's structural check, because Session only runs it inside its own snapshot
/// and the prototype edits the Draft locally. THROWAWAY — the real one is Session.structuralCheck.
private func warnings(for draft: Draft) -> [String] {
    var warnings: [String] = []
    switch draft.ticketType {
    case .story:
        if !draft.title.hasPrefix("As a ") {
            warnings.append("title does not match the Story convention")
        }
    case .bug, .chore:
        if draft.title.hasPrefix("As a ") || draft.title.isEmpty {
            warnings.append("title does not match the \(draft.ticketType.label) convention")
        }
    }
    if !draft.description.contains("---") || !draft.description.contains("- ") {
        warnings.append("a Definition of Done is missing")
    }
    let forbidden = ["Requirements", "Technical Notes", "Dependencies", "Out of Scope"]
    var leftVocabulary = false
    for line in draft.description.split(separator: "\n", omittingEmptySubsequences: false) {
        var heading = line.trimmingCharacters(in: .whitespaces)
        if heading.hasPrefix("#") { leftVocabulary = true }
        while heading.hasPrefix("#") {
            heading = heading.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        if forbidden.contains(where: {
            heading.compare($0, options: .caseInsensitive) == .orderedSame
        }) {
            warnings.append("description contains a forbidden heading")
            break
        }
    }
    if leftVocabulary { warnings.append("description leaves the Markdown vocabulary") }
    return warnings
}
