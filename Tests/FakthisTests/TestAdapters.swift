import Foundation
import Fakthis

struct ModelCompleteRequest: Equatable, Sendable {
    var system: String
    var user: String
    var screenshots: [Material]
}

actor FakeTranscriber: Transcriber {
    private var compileFinished: Bool
    private var takes: [String] = []
    private(set) var boostLists: [[String]] = []
    private var holdTranscribe = false
    private var transcribeWaiters: [CheckedContinuation<Void, Never>] = []
    private var failTranscribe = false

    init(compileFinished: Bool) {
        self.compileFinished = compileFinished
    }

    func finishCompile() {
        compileFinished = true
    }

    func enqueueTake(_ text: String) {
        takes.append(text)
    }

    func setHoldTranscribe(_ value: Bool) {
        holdTranscribe = value
        guard !value else { return }
        let waiters = transcribeWaiters
        transcribeWaiters = []
        waiters.forEach { $0.resume() }
    }

    func setFailTranscribe(_ value: Bool) {
        failTranscribe = value
    }

    func compileStatus() async -> CompileStatus {
        compileFinished ? .done : .inProgress
    }

    func transcribe(boostList: [String]) async throws -> String {
        boostLists.append(boostList)
        if failTranscribe { throw TranscribeFailed() }
        if holdTranscribe {
            await withCheckedContinuation { transcribeWaiters.append($0) }
        }
        guard !takes.isEmpty else { return "" }
        return takes.removeFirst()
    }
}

actor FakeSecrets: Secrets {
    private var storedJiraToken: String?
    private var storedModelKey: String?

    func storeJiraToken(_ token: String) async throws {
        storedJiraToken = token
    }

    func storeModelKey(_ key: String) async throws {
        storedModelKey = key
    }

    func jiraToken() async throws -> String {
        guard let storedJiraToken else { throw SecretAccessFailed() }
        return storedJiraToken
    }

    func modelKey() async throws -> String {
        guard let storedModelKey else { throw SecretAccessFailed() }
        return storedModelKey
    }
}

actor ScriptedModel: Model {
    var reply: GenerateReply
    var definitionOfDone: [String]
    var failGenerate = false
    private(set) var completeRequests: [ModelCompleteRequest] = []
    private var rawReply: String?
    private var holdComplete = false
    private var completeWaiters: [CheckedContinuation<Void, Never>] = []

    init(reply: GenerateReply, definitionOfDone: [String]) {
        self.reply = reply
        self.definitionOfDone = definitionOfDone
    }

    func replaceReply(_ reply: GenerateReply) {
        self.reply = reply
        rawReply = nil
    }

    func replaceRawReply(_ json: String) {
        rawReply = json
    }

    func replaceDefinitionOfDone(_ bullets: [String]) {
        definitionOfDone = bullets
    }

    func setFailGenerate(_ value: Bool) {
        failGenerate = value
    }

    func setHoldComplete(_ value: Bool) {
        holdComplete = value
        guard !value else { return }
        let waiters = completeWaiters
        completeWaiters = []
        waiters.forEach { $0.resume() }
    }

    func complete(system: String, user: String, screenshots: [Material]) async throws -> String {
        if failGenerate { throw ModelFailed() }
        if holdComplete {
            await withCheckedContinuation { completeWaiters.append($0) }
        }
        completeRequests.append(
            ModelCompleteRequest(system: system, user: user, screenshots: screenshots)
        )
        // Which pass this is comes off the instruction rather than a count of calls: the
        // Definition of Done pass also runs on its own when the PM asks for it after a
        // hand-edit, so "every second call" is not what tells them apart.
        if system.contains("JSON array of Definition of Done bullets") {
            return try jsonString(definitionOfDone)
        }
        if let rawReply { return rawReply }
        return try jsonString(reply)
    }
}

private func jsonString<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let text = String(data: data, encoding: .utf8) else { throw ModelFailed() }
    return text
}

struct UploadedAttachment: Equatable, Sendable {
    var key: TicketKey
    var filename: String
    var mimeType: String
    var data: Data
}

struct CreatedTicket: Equatable, Sendable {
    var title: String
    var descriptionWiki: String
    var jiraIssueType: String
    var completenessMarker: CompletenessMarker
    var parentKey: TicketKey?
}

struct UpdatedTicket: Equatable, Sendable {
    var key: TicketKey
    var title: String
    var descriptionWiki: String
    var completenessMarker: CompletenessMarker
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
    var updated: Date?
}

actor FakeJira: Jira {
    var unreachable = false
    var failUploads = false
    var failOnCreate: Int?
    var nextKey = TicketKey("FAK-1")
    private(set) var created: [CreatedTicket] = []
    private(set) var updated: [UpdatedTicket] = []
    private(set) var catalogPulls: [String] = []
    private(set) var fetchRewriteCalls: [TicketKey] = []
    private(set) var uploaded: [UploadedAttachment] = []
    private(set) var attachmentPolicyCalls = 0
    var uploadAttachmentCalls: Int { uploaded.count }
    private var seededEpics: [SeededEpic] = []
    private var seededIssues: [SeededIssue] = []
    private var seededComponentNames: [String] = []
    private var seededIssueTypes: [JiraIssueType] = []
    private var policy = AttachmentPolicy(enabled: true, uploadLimit: 10_485_760)

    private var holdPulls = false
    private var pullWaiters: [CheckedContinuation<Void, Never>] = []

    func createTicket(
        projectKey: String,
        title: String,
        descriptionWiki: String,
        jiraIssueType: String,
        parentKey: TicketKey?,
        completenessMarker: CompletenessMarker
    ) async throws -> TicketKey
    {
        if unreachable { throw JiraUnreachable() }
        if let failOnCreate, created.count + 1 == failOnCreate {
            throw JiraUnreachable()
        }
        created.append(
            CreatedTicket(
                title: title,
                descriptionWiki: descriptionWiki,
                jiraIssueType: jiraIssueType,
                completenessMarker: completenessMarker,
                parentKey: parentKey
            )
        )
        let key = nextKey
        if let number = Int(key.value.split(separator: "-").last ?? "") {
            nextKey = TicketKey("FAK-\(number + 1)")
        }
        return key
    }

    func updateTicket(
        key: TicketKey,
        title: String,
        descriptionWiki: String,
        completenessMarker: CompletenessMarker
    ) async throws {
        if unreachable { throw JiraUnreachable() }
        updated.append(
            UpdatedTicket(
                key: key,
                title: title,
                descriptionWiki: descriptionWiki,
                completenessMarker: completenessMarker
            )
        )
    }

    func attachmentPolicy() async throws -> AttachmentPolicy {
        attachmentPolicyCalls += 1
        if unreachable { throw JiraUnreachable() }
        return policy
    }

    func uploadAttachment(
        key: TicketKey,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws {
        if unreachable { throw JiraUnreachable() }
        if failUploads { throw JiraUnreachable() }
        uploaded.append(
            UploadedAttachment(key: key, filename: filename, mimeType: mimeType, data: data)
        )
    }

    func fetchIssueTypes(projectKey: String) async throws -> [JiraIssueType] {
        if unreachable { throw JiraUnreachable() }
        return seededIssueTypes
    }

    func fetchRewriteTarget(key: TicketKey) async throws -> RewriteTarget {
        fetchRewriteCalls.append(key)
        if unreachable { throw JiraUnreachable() }
        guard let issue = seededIssues.first(where: { $0.key == key.value }) else {
            throw JiraHTTPError(statusCode: 404)
        }
        return RewriteTarget(
            key: key,
            title: issue.title,
            description: issue.body,
            comments: issue.comments,
            updated: issue.updated ?? issue.created,
            jiraIssueType: issue.jiraIssueType
        )
    }

    private(set) var blocksLinks: [(blocker: TicketKey, blocked: TicketKey)] = []

    func createBlocksLink(blocker: TicketKey, blocked: TicketKey) async throws {
        if unreachable { throw JiraUnreachable() }
        blocksLinks.append((blocker, blocked))
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

    func seedIssueTypes(_ types: [JiraIssueType]) {
        seededIssueTypes = types
    }

    func replaceIssue(
        key: String,
        title: String,
        body: String,
        comments: [String],
        updated: Date
    ) {
        guard let index = seededIssues.firstIndex(where: { $0.key == key }) else { return }
        seededIssues[index].title = title
        seededIssues[index].body = body
        seededIssues[index].comments = comments
        seededIssues[index].updated = updated
    }

    func setAttachmentPolicy(_ policy: AttachmentPolicy) {
        self.policy = policy
    }

    func setHoldPulls(_ value: Bool) {
        holdPulls = value
        guard !value else { return }
        let waiters = pullWaiters
        pullWaiters = []
        waiters.forEach { $0.resume() }
    }

    func setFailUploads(_ value: Bool) {
        failUploads = value
    }

    func setFailOnCreate(_ value: Int?) {
        failOnCreate = value
    }

    func setUnreachable(_ value: Bool) {
        unreachable = value
    }
}
