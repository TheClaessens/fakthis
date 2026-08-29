import Foundation

public protocol Model: Sendable {
    func complete(system: String, user: String, screenshots: [Material]) async throws -> String
}

public protocol Transcriber: Sendable {
    func compileStatus() async -> CompileStatus
    func beginTake() async
    func transcribe(boostList: [String]) async throws -> String
}

extension Transcriber {
    public func beginTake() async {}
}

public enum TranscriberBoost {
    public static let cap = 100
    public static let hardStop = 230
    public static let whisperTokens = 223
}

public enum CompileStatus: Sendable {
    case inProgress
    case done
}

public protocol Secrets: Sendable {
    func storeJiraToken(_ token: String) async throws
    func storeModelKey(_ key: String) async throws
    func jiraToken() async throws -> String
    func modelKey() async throws -> String
}

public struct SecretAccessFailed: Error {
    public init() {}
}

public protocol Jira: Sendable {
    func createTicket(
        projectKey: String,
        title: String,
        descriptionWiki: String,
        jiraIssueType: String,
        parentKey: TicketKey?,
        completenessMarker: CompletenessMarker
    ) async throws -> TicketKey
    func pullCatalog(projectKey: String) async throws -> Catalog
    func updateTicket(
        key: TicketKey,
        title: String,
        descriptionWiki: String,
        completenessMarker: CompletenessMarker
    ) async throws
    func attachmentPolicy() async throws -> AttachmentPolicy
    func uploadAttachment(
        key: TicketKey,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws
    func fetchIssueTypes(projectKey: String) async throws -> [JiraIssueType]
    func fetchRewriteTarget(key: TicketKey) async throws -> RewriteTarget
    func createBlocksLink(blocker: TicketKey, blocked: TicketKey) async throws
}

public enum CompletenessMarker: Equatable, Sendable {
    case apply
    case clear

    public static let jiraLabel = "fakthis-open-questions"
}

public struct AttachmentPolicy: Equatable, Sendable {
    public var enabled: Bool
    public var uploadLimit: Int

    public init(enabled: Bool, uploadLimit: Int) {
        self.enabled = enabled
        self.uploadLimit = uploadLimit
    }
}

public struct JiraIssueType: Equatable, Sendable {
    public var name: String
    public var hierarchyLevel: Int
    public var subtask: Bool

    public init(name: String, hierarchyLevel: Int, subtask: Bool) {
        self.name = name
        self.hierarchyLevel = hierarchyLevel
        self.subtask = subtask
    }

    public var isStandard: Bool { !subtask && hierarchyLevel == 0 }
}

public struct RewriteTarget: Equatable, Sendable, Codable {
    public var key: TicketKey
    public var title: String
    public var description: String
    public var comments: [String]
    public var updated: Date
    public var jiraIssueType: String

    public init(
        key: TicketKey,
        title: String,
        description: String,
        comments: [String],
        updated: Date,
        jiraIssueType: String
    ) {
        self.key = key
        self.title = title
        self.description = description
        self.comments = comments
        self.updated = updated
        self.jiraIssueType = jiraIssueType
    }
}

public struct JiraUnreachable: Error {
    public init() {}
}

public struct ModelFailed: Error {
    public init() {}
}

public struct TranscribeFailed: Error {
    public init() {}
}

public struct JiraHTTPError: Error {
    public var statusCode: Int
    public init(statusCode: Int) {
        self.statusCode = statusCode
    }
}
