import Foundation

public protocol Model: Sendable {
    func complete(system: String, user: String, screenshots: [Material]) async throws -> String
}

/// Where a completion goes and what signs it: the provider's endpoint, the model id to ask for,
/// and the API key (§3.1, ADR-0001). None of it exists until the PM has been through first
/// launch, so it is read at the call rather than held from construction.
public struct ModelAccess: Sendable {
    public var endpoint: URL
    public var modelId: String
    public var apiKey: String

    public init(endpoint: URL, modelId: String, apiKey: String) {
        self.endpoint = endpoint
        self.modelId = modelId
        self.apiKey = apiKey
    }
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

/// The site a Jira call is made against and the account making it (§14, ADR-0002). The three
/// arrive together — hostname and email from settings, the token from Keychain — and, like
/// `ModelAccess`, none of them exists before first launch.
public struct JiraCredentials: Equatable, Sendable {
    public var host: String
    public var email: String
    public var apiToken: String

    public init(host: String, email: String, apiToken: String) {
        self.host = host
        self.email = email
        self.apiToken = apiToken
    }
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
