import Foundation
import Fakthis

struct ModelDraftRequest: Equatable, Sendable {
    var brainDump: String
    var catalog: Catalog
    var projectTerms: [String]
}

actor ScriptedModel: Model {
    var reply: GenerateReply
    let definitionOfDone: [String]
    private(set) var draftRequests: [ModelDraftRequest] = []
    private(set) var definitionOfDoneRequests: [String] = []

    init(reply: GenerateReply, definitionOfDone: [String]) {
        self.reply = reply
        self.definitionOfDone = definitionOfDone
    }

    func replaceReply(_ reply: GenerateReply) {
        self.reply = reply
    }

    func generateDraft(brainDump: String, catalog: Catalog, projectTerms: [String]) async throws
        -> GenerateReply
    {
        draftRequests.append(
            ModelDraftRequest(brainDump: brainDump, catalog: catalog, projectTerms: projectTerms)
        )
        return reply
    }

    func generateDefinitionOfDone(description: String) async throws -> [String] {
        definitionOfDoneRequests.append(description)
        return definitionOfDone
    }
}

struct CreatedTicket: Equatable, Sendable {
    var title: String
    var descriptionWiki: String
    var jiraIssueType: String
}

struct SeededEpic: Sendable {
    var key: String
    var name: String
    var status: String
    var description: String
}

struct SeededIssue: Sendable {
    var key: String
    var title: String
    var jiraIssueType: String
    var labels: [String]
    var parentEpicKey: String?
    var status: String
    var created: Date
    var body: String
    var comments: [String]
}

actor FakeJira: Jira {
    var unreachable = false
    var nextKey = TicketKey("FAK-1")
    private(set) var created: [CreatedTicket] = []
    private(set) var catalogPulls: [String] = []
    private(set) var attachmentPolicyCalls = 0
    private(set) var uploadAttachmentCalls = 0
    private var seededEpics: [SeededEpic] = []
    private var seededIssues: [SeededIssue] = []
    private var seededComponentNames: [String] = []

    private var holdPulls = false
    private var pullWaiters: [CheckedContinuation<Void, Never>] = []

    func createTicket(
        projectKey: String,
        title: String,
        descriptionWiki: String,
        jiraIssueType: String,
        parentKey: TicketKey?
    ) async throws -> TicketKey
    {
        if unreachable { throw JiraUnreachable() }
        created.append(
            CreatedTicket(
                title: title,
                descriptionWiki: descriptionWiki,
                jiraIssueType: jiraIssueType
            )
        )
        return nextKey
    }

    func updateTicket(
        key: TicketKey,
        title: String,
        descriptionWiki: String,
        completenessMarker: CompletenessMarker
    ) async throws {
        if unreachable { throw JiraUnreachable() }
    }

    func attachmentPolicy() async throws -> AttachmentPolicy {
        attachmentPolicyCalls += 1
        if unreachable { throw JiraUnreachable() }
        return AttachmentPolicy(enabled: true, uploadLimit: 10_485_760)
    }

    func uploadAttachment(
        key: TicketKey,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws {
        uploadAttachmentCalls += 1
        if unreachable { throw JiraUnreachable() }
    }

    func fetchIssueTypes(projectKey: String) async throws -> [JiraIssueType] {
        if unreachable { throw JiraUnreachable() }
        return []
    }

    func fetchRewriteTarget(key: TicketKey) async throws -> RewriteTarget {
        if unreachable { throw JiraUnreachable() }
        return RewriteTarget(
            key: key,
            title: "",
            description: "",
            comments: [],
            updated: Date(timeIntervalSince1970: 0),
            jiraIssueType: ""
        )
    }

    func createBlocksLink(blocker: TicketKey, blocked: TicketKey) async throws {
        if unreachable { throw JiraUnreachable() }
    }

    func pullCatalog(projectKey: String) async throws -> Catalog {
        catalogPulls.append(projectKey)
        if holdPulls {
            await withCheckedContinuation { pullWaiters.append($0) }
        }
        if unreachable { throw JiraUnreachable() }
        return Catalog(
            epics: seededEpics.map {
                CatalogEpic(key: TicketKey($0.key), name: $0.name, status: $0.status)
            },
            rows: seededIssues
                .sorted { $0.created > $1.created }
                .prefix(300)
                .map { issue in
                    CatalogRow(
                        key: TicketKey(issue.key),
                        title: issue.title,
                        jiraIssueType: issue.jiraIssueType,
                        labels: issue.labels,
                        parentEpicKey: issue.parentEpicKey.map(TicketKey.init),
                        status: issue.status,
                        created: issue.created
                    )
                },
            componentNames: seededComponentNames
        )
    }

    func seed(epics: [SeededEpic], issues: [SeededIssue], componentNames: [String]) {
        seededEpics = epics
        seededIssues = issues
        seededComponentNames = componentNames
    }

    func setHoldPulls(_ value: Bool) {
        holdPulls = value
        guard !value else { return }
        let waiters = pullWaiters
        pullWaiters = []
        waiters.forEach { $0.resume() }
    }

    func setUnreachable(_ value: Bool) {
        unreachable = value
    }
}
