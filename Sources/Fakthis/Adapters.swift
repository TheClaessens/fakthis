public struct GenerateReply: Equatable, Sendable {
    public var ticketType: TicketType
    public var title: String
    public var shortLabel: String
    public var description: String
    public var openQuestions: [String]

    public init(
        ticketType: TicketType,
        title: String,
        shortLabel: String,
        description: String,
        openQuestions: [String]
    ) {
        self.ticketType = ticketType
        self.title = title
        self.shortLabel = shortLabel
        self.description = description
        self.openQuestions = openQuestions
    }
}

public protocol Model: Sendable {
    func generateDraft(brainDump: String, catalog: Catalog, projectTerms: [String]) async throws
        -> GenerateReply
    func generateDefinitionOfDone(description: String) async throws -> [String]
}

public protocol Jira: Sendable {
    func createTicket(title: String, descriptionWiki: String, issueType: String) async throws
        -> TicketKey
    func pullCatalog(projectKey: String) async throws -> Catalog
}

public struct JiraUnreachable: Error {
    public init() {}
}
