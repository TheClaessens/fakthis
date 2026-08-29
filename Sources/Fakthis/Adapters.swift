import Foundation

public protocol Model: Sendable {
    func complete(system: String, user: String) async throws -> String
}

public protocol Jira: Sendable {
    func createTicket(
        projectKey: String,
        title: String,
        descriptionWiki: String,
        jiraIssueType: String,
        parentKey: TicketKey?
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

public enum CompletenessMarker: Sendable {
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
}

public struct RewriteTarget: Equatable, Sendable {
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

public struct JiraHTTPError: Error {
    public var statusCode: Int
    public init(statusCode: Int) {
        self.statusCode = statusCode
    }
}
