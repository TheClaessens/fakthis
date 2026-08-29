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
    func transcribe(terms: [String]) async throws -> String { throw TranscribeFailed() }
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
/// finished description — with one canned Story, whatever the brain-dump says.
private actor FixtureModel: Model {
    private var awaitingDefinitionOfDone = false

    func complete(system: String, user: String, screenshots: [Material]) async throws -> String {
        if awaitingDefinitionOfDone {
            awaitingDefinitionOfDone = false
            return json(FixtureContent.definitionOfDone)
        }
        awaitingDefinitionOfDone = true
        return json(FixtureContent.reply)
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
        AttachmentPolicy(enabled: true, uploadLimit: 10_485_760)
    }

    // Nothing below is reachable until Submit and Rewrite are wired.
    func createTicket(
        projectKey: String,
        title: String,
        descriptionWiki: String,
        jiraIssueType: String,
        parentKey: TicketKey?,
        completenessMarker: CompletenessMarker
    ) async throws -> TicketKey { throw JiraUnreachable() }

    func updateTicket(
        key: TicketKey,
        title: String,
        descriptionWiki: String,
        completenessMarker: CompletenessMarker
    ) async throws { throw JiraUnreachable() }

    func uploadAttachment(
        key: TicketKey,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws { throw JiraUnreachable() }

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

    static let reply = GenerateReply(
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

    static let definitionOfDone = [
        "The checkout summary recalculates its total from the current basket on page load",
        "A basket edited in another tab shows the corrected total on the checkout page",
        "The reported reproduction path no longer shows a stale figure on mobile web",
    ]
}
