import Foundation

public enum TicketType: String, Sendable, Codable, Equatable {
    case story
    case bug
    case chore
}

public struct TicketKey: Hashable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

public struct Project: Equatable, Sendable {
    public var key: String
    public var ticketTypeMapping: [TicketType: String]
    public var terms: [String]

    public init(key: String, ticketTypeMapping: [TicketType: String], terms: [String]) {
        self.key = key
        self.ticketTypeMapping = ticketTypeMapping
        self.terms = terms
    }
}

public struct Catalog: Equatable, Sendable {
    public var rows: [CatalogRow]

    public init(rows: [CatalogRow] = []) {
        self.rows = rows
    }
}

public struct CatalogRow: Equatable, Sendable {
    public var key: TicketKey
    public var title: String
    public var jiraIssueType: String
    public var shortLabel: String?
    public var ticketType: TicketType?

    public init(
        key: TicketKey,
        title: String,
        jiraIssueType: String,
        shortLabel: String? = nil,
        ticketType: TicketType? = nil
    ) {
        self.key = key
        self.title = title
        self.jiraIssueType = jiraIssueType
        self.shortLabel = shortLabel
        self.ticketType = ticketType
    }
}

public struct Draft: Equatable, Sendable {
    public var id: String
    public var ticketType: TicketType
    public var title: String
    public var shortLabel: String
    public var description: String
    public var openQuestions: [String]
    public var key: TicketKey?

    public init(
        id: String,
        ticketType: TicketType,
        title: String,
        shortLabel: String,
        description: String,
        openQuestions: [String],
        key: TicketKey? = nil
    ) {
        self.id = id
        self.ticketType = ticketType
        self.title = title
        self.shortLabel = shortLabel
        self.description = description
        self.openQuestions = openQuestions
        self.key = key
    }
}
