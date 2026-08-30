import Foundation

public enum TicketType: String, CaseIterable, Sendable, Codable, Equatable {
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

extension Settings {
    /// Where a Ticket lives once it exists. Jira is the system of record, so this is the whole
    /// of what Fakthis keeps of a Submitted Ticket: §3 holds `site` as the Jira Cloud hostname,
    /// and `/browse/{key}` is the page a developer opens.
    public func ticketURL(_ key: TicketKey) -> URL? {
        URL(string: "https://\(site)/browse/\(key.value)")
    }
}

/// The Ticket a Draft became. One fact answers two questions the window keeps asking — where
/// the work landed, and whether this is still an editor: §4 says that once the Jira issue
/// exists the Draft folder is an upload queue plus the key, never an editor again.
public struct SubmittedTicket: Equatable, Sendable {
    public var key: TicketKey
    /// Absent only when Fakthis has no site to build it from, which cannot happen after setup.
    public var url: URL?

    public init(key: TicketKey, url: URL?) {
        self.key = key
        self.url = url
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

    /// What is attached, without the bytes. A snapshot that carried an 84 MB recording would
    /// be copied every time the window read state. Only `Session` knows whether Jira refused
    /// the file, so it fills `blockedFromUpload` in.
    public func attached(blockedFromUpload: Bool = false) -> AttachedMaterial {
        AttachedMaterial(
            filename: filename,
            mimeType: mimeType,
            blockedFromUpload: blockedFromUpload
        )
    }

    public var isText: Bool { attached().isText }
    public var isScreenshot: Bool { attached().isScreenshot }
    public var isVideo: Bool { attached().isVideo }
    public var isMedia: Bool { attached().isMedia }
}

/// Material as a reader sees it: the name, the kind, and whether Jira will take it — which is
/// everything a chip on the composer needs and everything routing is decided on. The bytes stay
/// behind `Session`.
public struct AttachedMaterial: Equatable, Sendable {
    public var filename: String
    public var mimeType: String
    /// Oversize, or attachments disabled: `Session` keeps the file and never tries to upload it
    /// (§7). Without this the window would count it among the media that reached the Ticket and
    /// say a file was uploaded that Jira never received.
    public var blockedFromUpload: Bool

    public init(filename: String, mimeType: String, blockedFromUpload: Bool = false) {
        self.filename = filename
        self.mimeType = mimeType
        self.blockedFromUpload = blockedFromUpload
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

public struct Rewrite: Equatable, Sendable, Codable {
    public var liveTitle: String
    public var liveDescription: String
    public var comments: [String]
    public var commentsTruncated: Bool
    public var watchersNote: String
    public var stale: Bool

    public init(
        liveTitle: String,
        liveDescription: String,
        comments: [String],
        commentsTruncated: Bool,
        watchersNote: String,
        stale: Bool
    ) {
        self.liveTitle = liveTitle
        self.liveDescription = liveDescription
        self.comments = comments
        self.commentsTruncated = commentsTruncated
        self.watchersNote = watchersNote
        self.stale = stale
    }
}

public struct BatchSibling: Equatable, Sendable {
    public var id: String
    public var shortLabel: String
    public var epicKey: TicketKey?
    public var ticketType: TicketType?
    public var key: TicketKey?
    public var openQuestions: [String]

    public init(
        id: String,
        shortLabel: String,
        epicKey: TicketKey? = nil,
        ticketType: TicketType? = nil,
        key: TicketKey? = nil,
        openQuestions: [String] = []
    ) {
        self.id = id
        self.shortLabel = shortLabel
        self.epicKey = epicKey
        self.ticketType = ticketType
        self.key = key
        self.openQuestions = openQuestions
    }
}

public struct Batch: Equatable, Sendable {
    public var name: String
    public var siblings: [BatchSibling]
    public var focusedDraftId: String
    public var blocks: [String]
    public var offerRegenerateDraft1: Bool
    public var defaultEpicKey: TicketKey?
    public var duplicates: [BatchDuplicate]
    public var id: String

    public init(
        name: String,
        siblings: [BatchSibling],
        focusedDraftId: String,
        blocks: [String],
        offerRegenerateDraft1: Bool = false,
        defaultEpicKey: TicketKey? = nil,
        duplicates: [BatchDuplicate] = [],
        id: String = UUID().uuidString
    ) {
        self.name = name
        self.siblings = siblings
        self.focusedDraftId = focusedDraftId
        self.blocks = blocks
        self.offerRegenerateDraft1 = offerRegenerateDraft1
        self.defaultEpicKey = defaultEpicKey
        self.duplicates = duplicates
        self.id = id
    }
}

public struct BatchDuplicate: Equatable, Sendable {
    public var draftId: String
    public var shortLabel: String
    public var hit: DuplicateHit

    public init(draftId: String, shortLabel: String, hit: DuplicateHit) {
        self.draftId = draftId
        self.shortLabel = shortLabel
        self.hit = hit
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

    /// The description with the open-questions section at its foot, above the horizontal rule
    /// so the Definition of Done stays the closer. What the window renders and what Submit
    /// writes are the same string, so the screen and Jira cannot disagree about where it sits.
    public var descriptionWithOpenQuestions: String {
        guard !openQuestions.isEmpty else { return description }
        let bullets = openQuestions.map { "- \($0)" }.joined(separator: "\n")
        let section = "\(Draft.openQuestionsPreamble)\n\(bullets)"
        guard let horizontalRule = description.range(of: "\n---") else {
            return description + "\n\n" + section
        }
        return description.replacingCharacters(
            in: horizontalRule,
            with: "\n\n\(section)\n\n---"
        )
    }

    public static let openQuestionsPreamble = "The reporter skipped these questions:"
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

/// One turn of the chat, in the order it was said. `Session` has always written these to disk;
/// this is the same line, readable, so the conversation can be on screen instead of only in the
/// Draft folder.
public struct TranscriptLine: Equatable, Sendable, Codable {
    /// The two voices in the chat. Encoded as the strings already on disk, so a Draft written
    /// before this type existed still reads back.
    public enum Role: String, Equatable, Sendable, Codable {
        case pm = "user"
        case agent
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// One structural-check warning, and the field it is about.
///
/// §9 warns and never blocks, but "warns" is a placement problem: one undifferentiated list is
/// wrong at any size, because it either truncates or covers the Draft it is warning about. The
/// structural check is a **field signal**, so every warning it makes names the field it belongs
/// beside and the window anchors it there instead of collecting it into a detached list.
public struct StructuralWarning: Equatable, Sendable, Identifiable {
    /// The Draft fields the check can be about. There is no third: a Bug missing its steps is a
    /// warning about the description, and so is the field cap.
    public enum Field: String, Equatable, Sendable {
        case title
        case description
    }

    public var field: Field
    public var text: String

    public var id: String { "\(field.rawValue):\(text)" }

    public init(field: Field, text: String) {
        self.field = field
        self.text = text
    }
}

/// One signal about the Draft as a whole, resting as a mark in the gutter down the Draft's edge.
///
/// The counterpart to `StructuralWarning`: these are not about a field, so there is no field to
/// anchor them at. §9 names three — a failed Catalog refresh, oversize or disabled Material,
/// failed uploads. Deliberately absent: the open-questions section, which **is** its own warning
/// and already sits in the description, and the duplicate, which is a conversation event (§10).
/// None of them block Submit.
public struct DraftSignal: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case catalog
        case material
        case upload
    }

    public var kind: Kind
    public var text: String

    public var id: String { "\(kind.rawValue):\(text)" }

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}
