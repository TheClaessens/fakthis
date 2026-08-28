import Foundation

public enum TicketType: String, Sendable, Codable, Equatable {
    case story
    case bug
    case chore
}

public struct TicketKey: Hashable, Sendable, Codable {
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

public struct Catalog: Equatable, Sendable, Codable {
    public var epics: [CatalogEpic]
    public var rows: [CatalogRow]
    public var componentNames: [String]

    public init(
        epics: [CatalogEpic] = [],
        rows: [CatalogRow] = [],
        componentNames: [String] = []
    ) {
        self.epics = epics
        self.rows = rows
        self.componentNames = componentNames
    }
}

public struct CatalogEpic: Equatable, Sendable, Codable {
    public var key: TicketKey
    public var name: String
    public var status: String

    public init(key: TicketKey, name: String, status: String) {
        self.key = key
        self.name = name
        self.status = status
    }
}

public struct CatalogRow: Equatable, Sendable, Codable {
    public var key: TicketKey
    public var title: String
    public var jiraIssueType: String
    public var labels: [String]
    public var parentEpicKey: TicketKey?
    public var status: String
    public var created: Date?
    public var shortLabel: String?
    public var ticketType: TicketType?

    public init(
        key: TicketKey,
        title: String,
        jiraIssueType: String,
        labels: [String] = [],
        parentEpicKey: TicketKey? = nil,
        status: String = "",
        created: Date? = nil,
        shortLabel: String? = nil,
        ticketType: TicketType? = nil
    ) {
        self.key = key
        self.title = title
        self.jiraIssueType = jiraIssueType
        self.labels = labels
        self.parentEpicKey = parentEpicKey
        self.status = status
        self.created = created
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

extension Catalog {
    func mergingPull(_ pulled: Catalog) -> Catalog {
        let local = rows.filter { $0.shortLabel != nil || $0.ticketType != nil }
        let localByKey = Dictionary(uniqueKeysWithValues: local.map { ($0.key, $0) })
        var merged = pulled.rows.map { row in
            var row = row
            if let kept = localByKey[row.key] {
                row.shortLabel = kept.shortLabel
                row.ticketType = kept.ticketType
            }
            return row
        }
        let pulledKeys = Set(merged.map(\.key))
        merged.append(contentsOf: local.filter { !pulledKeys.contains($0.key) })
        return Catalog(
            epics: pulled.epics,
            rows: merged,
            componentNames: pulled.componentNames
        )
    }
}
