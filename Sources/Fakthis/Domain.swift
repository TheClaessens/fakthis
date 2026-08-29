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

public struct Settings: Equatable, Sendable, Codable {
    public var site: String
    public var email: String
    public var provider: String
    public var modelId: String

    public init(site: String, email: String, provider: String, modelId: String) {
        self.site = site
        self.email = email
        self.provider = provider
        self.modelId = modelId
    }
}

public struct ProposedProject: Equatable, Sendable {
    public var key: String
    public var mapping: [TicketType: String]
    public var standardJiraIssueTypes: [String]

    public init(key: String, mapping: [TicketType: String], standardJiraIssueTypes: [String]) {
        self.key = key
        self.mapping = mapping
        self.standardJiraIssueTypes = standardJiraIssueTypes
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

public struct Material: Equatable, Sendable {
    public var filename: String
    public var mimeType: String
    public var data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }

    public var isText: Bool { mimeType.hasPrefix("text/") }
    public var isScreenshot: Bool { mimeType.hasPrefix("image/") }
    public var isVideo: Bool { mimeType.hasPrefix("video/") }
    public var isMedia: Bool { isScreenshot || isVideo }
}

public enum DuplicateHit: Equatable, Sendable {
    case catalog(key: TicketKey, shortLabel: String?, title: String)
    case localDraft(id: String, shortLabel: String, title: String)

    public var key: TicketKey? {
        if case .catalog(let key, _, _) = self { return key }
        return nil
    }

    public var draftId: String? {
        if case .localDraft(let id, _, _) = self { return id }
        return nil
    }

    public var shortLabel: String? {
        switch self {
        case .catalog(_, let shortLabel, _): shortLabel
        case .localDraft(_, let shortLabel, _): shortLabel
        }
    }

    public var title: String {
        switch self {
        case .catalog(_, _, let title): title
        case .localDraft(_, _, let title): title
        }
    }
}

public struct RelatedHit: Equatable, Sendable {
    public var key: TicketKey
    public var title: String
    public var ticked: Bool

    public init(key: TicketKey, title: String, ticked: Bool = false) {
        self.key = key
        self.title = title
        self.ticked = ticked
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

public struct GenerateReply: Equatable, Sendable, Codable {
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ticketType = (try? container.decode(TicketType.self, forKey: .ticketType)) ?? .story
        title = try container.decode(String.self, forKey: .title)
        shortLabel = try container.decode(String.self, forKey: .shortLabel)
        description = try container.decode(String.self, forKey: .description)
        openQuestions = try container.decode([String].self, forKey: .openQuestions)
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

extension TicketType {
    public static func mapping(from jiraIssueTypes: [JiraIssueType]) -> [TicketType: String] {
        let standard = jiraIssueTypes.filter(\.isStandard)
        let fallback = standard.first?.name ?? "Task"
        func matchingJiraName(_ name: String) -> String {
            standard.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }?
                .name ?? fallback
        }
        return [
            .story: matchingJiraName("Story"),
            .bug: matchingJiraName("Bug"),
            .chore: matchingJiraName("Chore"),
        ]
    }
}
