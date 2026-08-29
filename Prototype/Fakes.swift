// THROWAWAY PROTOTYPE. Copied from Tests/FakthisTests/TestAdapters.swift, trimmed to what
// the prototype drives. A test target is not importable from an executable target, so this
// is a copy rather than a reuse. Do not fold this file back into main.

import Foundation
import Fakthis

actor FakeTranscriber: Transcriber {
    private var compileFinished: Bool
    init(compileFinished: Bool) { self.compileFinished = compileFinished }
    func compileStatus() async -> CompileStatus { compileFinished ? .done : .inProgress }
}

actor FakeSecrets: Secrets {
    private var storedJiraToken: String?
    private var storedModelKey: String?
    func storeJiraToken(_ token: String) async throws { storedJiraToken = token }
    func storeModelKey(_ key: String) async throws { storedModelKey = key }
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
    private var awaitingDefinitionOfDone = false

    init(reply: GenerateReply, definitionOfDone: [String]) {
        self.reply = reply
        self.definitionOfDone = definitionOfDone
    }

    func replace(reply: GenerateReply, definitionOfDone: [String]) {
        self.reply = reply
        self.definitionOfDone = definitionOfDone
    }

    func complete(system: String, user: String, screenshots: [Material]) async throws -> String {
        if awaitingDefinitionOfDone {
            awaitingDefinitionOfDone = false
            return try jsonString(definitionOfDone)
        }
        awaitingDefinitionOfDone = true
        return try jsonString(reply)
    }
}

private func jsonString<T: Encodable>(_ value: T) throws -> String {
    String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "{}"
}

actor FakeJira: Jira {
    var unreachable = false
    var failUploads = false
    var nextKey = TicketKey("FAK-412")
    private var seededEpics: [CatalogEpic] = []
    private var seededRows: [CatalogRow] = []
    private var seededComponentNames: [String] = []
    private var seededIssueTypes: [JiraIssueType] = []

    func seed(
        epics: [CatalogEpic],
        rows: [CatalogRow],
        componentNames: [String],
        issueTypes: [JiraIssueType]
    ) {
        seededEpics = epics
        seededRows = rows
        seededComponentNames = componentNames
        seededIssueTypes = issueTypes
    }

    func setUnreachable(_ value: Bool) { unreachable = value }
    func setFailUploads(_ value: Bool) { failUploads = value }

    func createTicket(
        projectKey: String,
        title: String,
        descriptionWiki: String,
        jiraIssueType: String,
        parentKey: TicketKey?,
        completenessMarker: CompletenessMarker
    ) async throws -> TicketKey {
        if unreachable { throw JiraUnreachable() }
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
        if unreachable { throw JiraUnreachable() }
        return AttachmentPolicy(enabled: true, uploadLimit: 10_485_760)
    }

    func uploadAttachment(
        key: TicketKey,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws {
        if unreachable || failUploads { throw JiraUnreachable() }
    }

    func fetchIssueTypes(projectKey: String) async throws -> [JiraIssueType] {
        if unreachable { throw JiraUnreachable() }
        return seededIssueTypes
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
        if unreachable { throw JiraUnreachable() }
        return Catalog(epics: seededEpics, rows: seededRows, componentNames: seededComponentNames)
    }
}
