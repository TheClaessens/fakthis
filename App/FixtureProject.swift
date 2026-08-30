import Foundation
import Fakthis

// The app opens on a fixture Project because real setup — first launch, Keychain, a Jira project
// key, a model provider — is a later ticket. Everything in this file is scaffolding for that
// ticket to delete: the adapters answer from canned data instead of the network, so the window
// can be opened and looked at without credentials.
//
// `Session` itself is real, and so is the disk: the Project and the Draft are written to the
// Application Support tree in §4, which is what makes a restart return to the Draft.

enum FixtureProject {
    static let key = "FAK"

    /// §4. Not Documents, not iCloud, not the bundle.
    static func applicationSupport() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return root.appending(component: "Fakthis")
    }

    static func session() -> Session {
        Session(
            applicationSupport: applicationSupport(),
            model: FixtureModel(),
            jira: FixtureJira(),
            transcriber: FixtureTranscriber(),
            secrets: FixtureSecrets()
        )
    }

    /// Scaffolding for looking at the window's later states without pressing anything: launch
    /// with `--submit` and the fixture Submits on open, which is the only way to see the footer
    /// after Submit on a machine that will not grant synthetic clicks. Goes with the rest of
    /// this file when #35 lands real setup.
    static var submitOnOpen: Bool { CommandLine.arguments.contains("--submit") }

    /// The same scaffolding for the workbench: launch with `--generate` and the fixture types a
    /// brain-dump and presses Generate on open, so the three columns can be looked at without a
    /// synthetic click. Goes with the rest of this file when #35 lands real setup.
    static var generateOnOpen: Bool { CommandLine.arguments.contains("--generate") }

    /// The same scaffolding for the gutter: launch with `--signals` and the fixture attaches one
    /// screenshot Jira is too small to take and one video it will refuse at upload. That is one
    /// resting mark before Submit and two after it — the single-signal case and the several-
    /// signal case, which are judged differently. Layout is judged by looking at it, and there
    /// is no other way to get a signal onto a Draft without a synthetic drag.
    static var signalsOnOpen: Bool { CommandLine.arguments.contains("--signals") }

    /// And for the Definition of Done offer, which only a hand-edit arms: launch with `--edited`
    /// and the fixture appends a sentence to the description the way the keyboard would.
    static var editDescriptionOnOpen: Bool { CommandLine.arguments.contains("--edited") }

    static let editedSentence = "\n\nThe payment step reads the same figure."

    /// What it attaches. Sized against the policy below: the screenshot is over the limit and is
    /// refused at attach, the video is under it and is refused by the fixture Jira at upload,
    /// which is where the `fail-` prefix is read.
    static let signalMaterial = [
        Material(
            filename: "pick.png",
            mimeType: "image/png",
            data: Data("this-screenshot-is-oversize".utf8)
        ),
        Material(
            filename: "fail-repro.mp4",
            mimeType: "video/mp4",
            data: Data("fake-mp4".utf8)
        ),
    ]

    /// What it types. Sixty spoken words about a Ticket the canned replies answer.
    static let brainDump =
        "the checkout total is wrong on mobile, it shows the total from before you changed "
        + "the basket and only fixes itself if you refresh"

    /// Walk `Session` up to "a Project exists", once. On every later launch the Project is
    /// already on disk and `Session` loads it, so this does nothing.
    static func open(_ session: Session) async throws -> Session.State {
        var state = try await session.state()
        if state.project != nil { return state }

        state = try await session.perform(
            .saveCredentials(
                Settings(
                    site: "example.atlassian.net",
                    email: "pm@example.com",
                    provider: "fixture",
                    modelId: "fixture"
                ),
                jiraToken: "fixture",
                modelKey: "fixture"
            )
        )
        state = try await session.perform(.enterProjectKey(key))
        guard let proposed = state.proposedProject else { return state }
        return try await session.perform(.confirmProject(mapping: proposed.mapping))
    }
}

// MARK: - Adapters

private actor FixtureTranscriber: Transcriber {
    func compileStatus() async -> CompileStatus { .done }
    func transcribe(boostList: [String]) async throws -> String { throw TranscribeFailed() }
}

private actor FixtureSecrets: Secrets {
    private var jira: String?
    private var model: String?
    func storeJiraToken(_ token: String) async throws { jira = token }
    func storeModelKey(_ key: String) async throws { model = key }
    func jiraToken() async throws -> String {
        guard let jira else { throw SecretAccessFailed() }
        return jira
    }
    func modelKey() async throws -> String {
        guard let model else { throw SecretAccessFailed() }
        return model
    }
}

/// Answers the two passes `Session` makes — the Draft, then the Definition of Done read from the
/// finished description — with one canned reply per Ticket type, whatever the brain-dump says.
///
/// It reads the type out of the reshape instruction `Session` writes, which is the only way a
/// canned model can show that changing the type reshapes the Draft against the new template.
private actor FixtureModel: Model {
    /// Which pass this is comes off the instruction, not off a count of calls: the Definition of
    /// Done pass also runs on its own when the PM answers the offer a hand-edit armed.
    private var lastTicketType = TicketType.story

    func complete(system: String, user: String, screenshots: [Material]) async throws -> String {
        if system.contains("JSON array of Definition of Done bullets") {
            return json(FixtureContent.definitionOfDone(lastTicketType))
        }
        let ticketType = TicketType.allCases.first { system.contains("as a \($0.rawValue)") } ?? .story
        lastTicketType = ticketType
        return json(FixtureContent.reply(ticketType))
    }

    private func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private actor FixtureJira: Jira {
    func fetchIssueTypes(projectKey: String) async throws -> [JiraIssueType] {
        FixtureContent.issueTypes
    }

    func pullCatalog(projectKey: String) async throws -> Catalog {
        Catalog(
            epics: FixtureContent.epics,
            rows: FixtureContent.rows,
            componentNames: ["checkout", "pricing", "mobile-web"]
        )
    }

    func attachmentPolicy() async throws -> AttachmentPolicy {
        AttachmentPolicy(
            enabled: true,
            uploadLimit: FixtureProject.signalsOnOpen ? 12 : 10_485_760
        )
    }

    private var nextNumber = 301

    func createTicket(
        projectKey: String,
        title: String,
        descriptionWiki: String,
        jiraIssueType: String,
        parentKey: TicketKey?,
        completenessMarker: CompletenessMarker
    ) async throws -> TicketKey {
        defer { nextNumber += 1 }
        return TicketKey("\(projectKey)-\(nextNumber)")
    }

    func updateTicket(
        key: TicketKey,
        title: String,
        descriptionWiki: String,
        completenessMarker: CompletenessMarker
    ) async throws { throw JiraUnreachable() }

    /// Media whose name starts with `fail-` never uploads; everything else does. Naming the
    /// file is how the upload step after create is put into either of the two states it has to
    /// be able to show — uploaded, or waiting on a retry.
    func uploadAttachment(
        key: TicketKey,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws {
        if filename.hasPrefix("fail-") { throw JiraUnreachable() }
    }

    func fetchRewriteTarget(key: TicketKey) async throws -> RewriteTarget {
        throw JiraUnreachable()
    }

    func createBlocksLink(blocker: TicketKey, blocked: TicketKey) async throws {
        throw JiraUnreachable()
    }
}

// MARK: - Canned content

private enum FixtureContent {
    static let issueTypes = [
        JiraIssueType(name: "Story", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Bug", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Task", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Epic", hierarchyLevel: 1, subtask: false),
        JiraIssueType(name: "Sub-task", hierarchyLevel: -1, subtask: true),
    ]

    static let epics = [
        CatalogEpic(key: TicketKey("FAK-100"), name: "Checkout", status: "In Progress"),
        CatalogEpic(key: TicketKey("FAK-140"), name: "Basket and pricing", status: "In Progress"),
    ]

    static let rows = [
        CatalogRow(
            key: TicketKey("FAK-198"),
            title: "Move basket total onto the shared pricing service",
            jiraIssueType: "Task",
            parentEpicKey: TicketKey("FAK-140"),
            status: "Done",
            shortLabel: "Basket total to pricing service",
            ticketType: .chore
        ),
        CatalogRow(
            key: TicketKey("FAK-274"),
            title: "Checkout summary redesign",
            jiraIssueType: "Story",
            parentEpicKey: TicketKey("FAK-100"),
            status: "To Do"
        ),
    ]

    /// One canned reply per Ticket type, so a type change visibly reshapes the Draft against
    /// the new template — a Bug's steps and expected-against-actual, a Chore's one paragraph.
    static func reply(_ ticketType: TicketType) -> GenerateReply {
        switch ticketType {
        case .story: story
        case .bug: bug
        case .chore: chore
        }
    }

    static func definitionOfDone(_ ticketType: TicketType) -> [String] {
        switch ticketType {
        case .story, .bug: storyDefinitionOfDone
        case .chore: choreDefinitionOfDone
        }
    }

    static let story = GenerateReply(
        ticketType: .story,
        title: "As a shopper I want the checkout total to match my current basket "
            + "so that I never pay against a stale figure",
        shortLabel: "Stale checkout total",
        description: """
            **Northbeam** shoppers on mobile web see a checkout total carried over from before \
            their last basket change. The figure corrects itself on a manual refresh, so the \
            **basket** holds the right contents and the **checkout summary** is reading a total \
            it was handed rather than one it asked for. Support has taken this three times this \
            month, most recently from the Northbeam account team.

            The checkout summary should recalculate from the current basket on load, going to \
            the shared pricing service the same way the basket page does since FAK-198 moved \
            that call. Scope is the summary figure only; the payment step is untouched by this \
            Ticket.
            """,
        openQuestions: [
            "Does the stale total reach the payment step, or only the checkout summary?",
            "Should the recalculation run on every checkout load, or only when the basket "
                + "changed since the last render?",
        ]
    )

    static let bug = GenerateReply(
        ticketType: .bug,
        title: "Checkout total is the one from before the last basket change",
        shortLabel: "Stale checkout total",
        description: """
            The **checkout summary** shows a total carried over from before the shopper's last \
            basket change.

            **Steps to reproduce:**

            1. Add two items to the **basket** on mobile web
            2. Remove one item
            3. Go to checkout without refreshing

            **Expected:** the summary total matches the current basket.

            **Actual:** the summary shows the total from before the removal, and corrects itself \
            only on a manual refresh.

            **Environment:** mobile web, reported by the Northbeam account team three times this \
            month.
            """,
        openQuestions: [
            "Does the stale total reach the payment step, or only the checkout summary?",
            "Which browsers has this been seen on?",
        ]
    )

    static let chore = GenerateReply(
        ticketType: .chore,
        title: "Move the checkout summary total onto the shared pricing service",
        shortLabel: "Checkout total to pricing service",
        description: """
            The **checkout summary** still computes its own total instead of asking the shared \
            pricing service, which the **basket** page has used since FAK-198. Moving the \
            checkout call onto the same service leaves one place that knows how a total is \
            worked out.
            """,
        openQuestions: []
    )

    static let storyDefinitionOfDone = [
        "The checkout summary recalculates its total from the current basket on page load",
        "A basket edited in another tab shows the corrected total on the checkout page",
        "The reported reproduction path no longer shows a stale figure on mobile web",
    ]

    static let choreDefinitionOfDone = [
        "The checkout summary asks the shared pricing service for its total",
        "The summary's own total calculation is gone",
    ]
}
