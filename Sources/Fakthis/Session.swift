import Foundation

public actor Session {
    public enum Intent: Sendable {
        case typeBrainDump(String)
        case generate
        case submit
    }

    public struct State: Equatable, Sendable {
        public var field: String
        public var draft: Draft?
        public var catalog: Catalog
    }

    private let project: Project
    private let applicationSupport: URL
    private let model: any Model
    private let jira: any Jira

    private var field = ""
    private var draft: Draft?
    private var catalog = Catalog()

    public init(
        project: Project,
        applicationSupport: URL,
        model: any Model,
        jira: any Jira
    ) {
        self.project = project
        self.applicationSupport = applicationSupport
        self.model = model
        self.jira = jira
    }

    public func state() throws -> State {
        try loadDraftIfMissing()
        return snapshot()
    }

    public func perform(_ intent: Intent) async throws -> State {
        try loadDraftIfMissing()
        switch intent {
        case .typeBrainDump(let text):
            field = text
        case .generate:
            try await generate()
        case .submit:
            try await submit()
        }
        return snapshot()
    }

    private func submit() async throws {
        guard var draft, draft.key == nil,
            let issueType = project.ticketTypeMapping[draft.ticketType]
        else {
            return
        }
        let key: TicketKey
        do {
            key = try await jira.createTicket(
                title: draft.title,
                descriptionWiki: wikiMarkup(from: draft.description),
                issueType: issueType
            )
        } catch is JiraUnreachable {
            return
        }
        draft.key = key
        self.draft = draft
        catalog.rows.append(
            CatalogRow(
                key: key,
                title: draft.title,
                jiraIssueType: issueType,
                shortLabel: draft.shortLabel,
                ticketType: draft.ticketType
            )
        )
        try persistDraft()
    }

    private func generate() async throws {
        if draft?.key != nil { return }
        let generated = try await model.generateDraft(
            brainDump: field,
            catalog: catalog,
            projectTerms: project.terms
        )
        let done = try await model.generateDefinitionOfDone(description: generated.description)
        let bullets = done.map { "- \($0)" }.joined(separator: "\n")
        let description = """
            \(generated.description)

            ---

            **Definition of Done:**

            \(bullets)
            """
        draft = Draft(
            id: draft?.id ?? UUID().uuidString,
            ticketType: generated.ticketType,
            title: generated.title,
            shortLabel: generated.shortLabel,
            description: description,
            openQuestions: generated.openQuestions
        )
        try persistDraft()
        try persistTranscript()
    }

    private func loadDraftIfMissing() throws {
        if draft != nil { return }
        draft = try loadInProgressDraft()
    }

    private func loadInProgressDraft() throws -> Draft? {
        let root = draftsRoot()
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let folders = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            let sidecarURL = folder.appending(component: "draft.json")
            guard FileManager.default.fileExists(atPath: sidecarURL.path) else { continue }
            let sidecar = try JSONDecoder().decode(Sidecar.self, from: Data(contentsOf: sidecarURL))
            if sidecar.key != nil { continue }
            let description = try String(
                contentsOf: folder.appending(component: "description.md"),
                encoding: .utf8
            )
            return Draft(
                id: folder.lastPathComponent,
                ticketType: sidecar.ticketType,
                title: sidecar.title,
                shortLabel: sidecar.shortLabel,
                description: description,
                openQuestions: sidecar.openQuestions
            )
        }
        return nil
    }

    private func persistDraft() throws {
        guard let draft else { return }
        let folder = draftFolder(id: draft.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let sidecar = Sidecar(
            ticketType: draft.ticketType,
            title: draft.title,
            shortLabel: draft.shortLabel,
            openQuestions: draft.openQuestions,
            key: draft.key?.value
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(sidecar).write(to: folder.appending(component: "draft.json"))
        try draft.description.write(
            to: folder.appending(component: "description.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func persistTranscript() throws {
        guard let draft else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let line = try encoder.encode(TranscriptLine(role: "user", text: field))
        guard let jsonl = String(data: line, encoding: .utf8) else { return }
        try (jsonl + "\n").write(
            to: draftFolder(id: draft.id).appending(component: "transcript.jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func draftFolder(id: String) -> URL {
        draftsRoot().appending(component: id)
    }

    private func draftsRoot() -> URL {
        applicationSupport
            .appending(component: "projects")
            .appending(component: project.key)
            .appending(component: "drafts")
    }

    private struct Sidecar: Codable {
        var ticketType: TicketType
        var title: String
        var shortLabel: String
        var openQuestions: [String]
        var key: String?
    }

    private struct TranscriptLine: Codable {
        var role: String
        var text: String
    }

    private func snapshot() -> State {
        State(field: field, draft: draft, catalog: catalog)
    }
}

private func wikiMarkup(from markdown: String) -> String {
    markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
        var text = String(line)
        if text.trimmingCharacters(in: .whitespaces) == "---" {
            return "----"
        }
        text = boldToWiki(text)
        if text.hasPrefix("- ") {
            return "* " + text.dropFirst(2)
        }
        return text
    }.joined(separator: "\n")
}

private func boldToWiki(_ text: String) -> String {
    var result = ""
    var rest = text[...]
    while let open = rest.range(of: "**") {
        result += rest[..<open.lowerBound]
        rest = rest[open.upperBound...]
        guard let close = rest.range(of: "**") else {
            result += "**"
            result += rest
            rest = rest[rest.endIndex...]
            break
        }
        result += "*"
        result += rest[..<close.lowerBound]
        result += "*"
        rest = rest[close.upperBound...]
    }
    result += rest
    return result
}
