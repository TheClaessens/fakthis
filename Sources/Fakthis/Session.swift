import Foundation

private let catalogStaleAfter: TimeInterval = 60 * 60

public actor Session {
    public enum Intent: Sendable {
        case typeBrainDump(String)
        case generate
        case submit
        case saveCredentials(Settings, jiraToken: String, modelKey: String)
        case enterProjectKey(String)
        case confirmProject(mapping: [TicketType: String])
    }

    public struct State: Equatable, Sendable {
        public var field: String
        public var draft: Draft?
        public var catalog: Catalog
        public var aneCompileInProgress: Bool
        public var settings: Settings?
        public var project: Project?
        public var proposedProject: ProposedProject?
        public var textMaterialWarning: String?
    }

    private var project: Project?
    private let applicationSupport: URL
    private let model: any Model
    private let jira: any Jira
    private let transcriber: any Transcriber
    private let secrets: any Secrets

    private var field = ""
    private var draft: Draft?
    private var catalog = Catalog()
    private var aneCompileInProgress = true
    private var settings: Settings?
    private var proposedProject: ProposedProject?
    private var textMaterialWarning: String?

    public init(
        applicationSupport: URL,
        model: any Model,
        jira: any Jira,
        transcriber: any Transcriber,
        secrets: any Secrets
    ) {
        self.applicationSupport = applicationSupport
        self.model = model
        self.jira = jira
        self.transcriber = transcriber
        self.secrets = secrets
    }

    public func state() async throws -> State {
        try await load()
        startBackgroundRefreshIfStale()
        return snapshot()
    }

    public func perform(_ intent: Intent) async throws -> State {
        try await load()
        switch intent {
        case .typeBrainDump(let text):
            startBackgroundRefreshIfStale()
            field = text
        case .generate:
            try await pullCatalogIfNeverPulled()
            startBackgroundRefreshIfStale()
            try await generate()
        case .submit:
            startBackgroundRefreshIfStale()
            try await submit()
        case .saveCredentials(let settings, let jiraToken, let modelKey):
            try await saveCredentials(
                settings: settings,
                jiraToken: jiraToken,
                modelKey: modelKey
            )
        case .enterProjectKey(let key):
            try await enterProjectKey(key)
        case .confirmProject(let mapping):
            try await confirmProject(mapping: mapping)
        }
        return snapshot()
    }

    private func load() async throws {
        await refreshCompileStatus()
        try loadSettingsFromDiskIfNeeded()
        try loadProjectFromDiskIfNeeded()
        try loadDraftIfMissing()
        try loadCatalogFromDiskIfNeeded()
    }

    private func saveCredentials(
        settings: Settings,
        jiraToken: String,
        modelKey: String
    ) async throws {
        guard !aneCompileInProgress else { return }
        try await secrets.storeJiraToken(jiraToken)
        try await secrets.storeModelKey(modelKey)
        self.settings = settings
        try persistSettings()
    }

    private func enterProjectKey(_ key: String) async throws {
        guard settings != nil, !aneCompileInProgress else { return }
        let types: [JiraIssueType]
        do {
            types = try await jira.fetchIssueTypes(projectKey: key)
        } catch is JiraUnreachable {
            return
        }
        let standard = types.filter(\.isStandard)
        proposedProject = ProposedProject(
            key: key,
            mapping: TicketType.mapping(from: types),
            standardJiraIssueTypes: standard.map(\.name)
        )
    }

    private func confirmProject(mapping: [TicketType: String]) async throws {
        guard let proposedProject, settings != nil, !aneCompileInProgress else { return }
        project = Project(
            key: proposedProject.key,
            ticketTypeMapping: mapping,
            terms: []
        )
        self.proposedProject = nil
        textMaterialWarning = "Text Material is sent to the model provider."
        try persistProject()
        try await pullCatalogIfNeverPulled()
    }

    private func persistProject() throws {
        guard let project, let folder = projectRoot() else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let file = ProjectFile(
            ticketTypeMapping: project.ticketTypeMapping,
            terms: project.terms
        )
        try encoder.encode(file).write(to: folder.appending(component: "project.json"))
    }

    private func refreshCompileStatus() async {
        aneCompileInProgress = await transcriber.compileStatus() == .inProgress
    }

    private func submit() async throws {
        guard var draft, draft.key == nil,
            let project,
            let jiraIssueType = project.ticketTypeMapping[draft.ticketType]
        else {
            return
        }
        let key: TicketKey
        do {
            key = try await jira.createTicket(
                projectKey: project.key,
                title: draft.title,
                descriptionWiki: wikiMarkup(from: draft.description),
                jiraIssueType: jiraIssueType,
                parentKey: nil
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
                jiraIssueType: jiraIssueType,
                shortLabel: draft.shortLabel,
                ticketType: draft.ticketType
            )
        )
        try persistDraft()
        try persistCatalog()
    }

    private var catalogLoaded = false
    private var catalogPulledAt: Date?
    private var firstPullFailed = false
    private var refreshTask: Task<Void, Never>?

    private func pullCatalogIfNeverPulled() async throws {
        guard let project else { return }
        guard catalogPulledAt == nil, !firstPullFailed else { return }
        do {
            try applySuccessfulPull(try await jira.pullCatalog(projectKey: project.key))
        } catch is JiraUnreachable {
            firstPullFailed = true
        } catch {
            throw error
        }
    }

    private func startBackgroundRefreshIfStale() {
        guard project != nil else { return }
        guard let catalogPulledAt else { return }
        guard Date().timeIntervalSince(catalogPulledAt) > catalogStaleAfter else { return }
        guard refreshTask == nil else { return }
        refreshTask = Task { await self.refreshCatalog() }
    }

    private func refreshCatalog() async {
        defer { refreshTask = nil }
        guard let project else { return }
        do {
            try applySuccessfulPull(try await jira.pullCatalog(projectKey: project.key))
        } catch {
            return
        }
    }

    private func applySuccessfulPull(_ pulled: Catalog) throws {
        catalog = catalog.mergingPull(pulled)
        catalogPulledAt = Date()
        try persistCatalog()
    }

    private func loadCatalogFromDiskIfNeeded() throws {
        if catalogLoaded { return }
        catalogLoaded = true
        guard let folder = projectRoot() else { return }
        let url = folder.appending(component: "catalog.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(CatalogFile.self, from: Data(contentsOf: url))
        catalog = file.catalog
        catalogPulledAt = file.pulledAt
    }

    private func persistCatalog() throws {
        guard let folder = projectRoot() else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let file = CatalogFile(pulledAt: catalogPulledAt, catalog: catalog)
        try encoder.encode(file).write(to: folder.appending(component: "catalog.json"))
    }

    private struct CatalogFile: Codable {
        var pulledAt: Date?
        var catalog: Catalog
    }

    private func generate() async throws {
        if draft?.key != nil { return }
        guard let project else { return }
        let generated: GenerateReply
        let done: [String]
        do {
            let prefix = stuffedPrefix(catalog: catalog, projectTerms: project.terms)
            generated = try decodeJSON(
                try await model.complete(
                    system: systemPrompt(prefix: prefix, instruction: generateInstruction),
                    user: field
                )
            )
            done = try decodeJSON(
                try await model.complete(
                    system: systemPrompt(
                        prefix: prefix,
                        instruction: definitionOfDoneInstruction
                    ),
                    user: generated.description
                )
            )
        } catch is ModelFailed {
            return
        }
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
        guard project != nil else { return }
        draft = try loadInProgressDraft()
    }

    private var projectLoaded = false
    private var settingsLoaded = false

    private func loadSettingsFromDiskIfNeeded() throws {
        if settingsLoaded { return }
        settingsLoaded = true
        let url = applicationSupport.appending(component: "settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
    }

    private func persistSettings() throws {
        guard let settings else { return }
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(settings).write(
            to: applicationSupport.appending(component: "settings.json")
        )
    }

    private func loadProjectFromDiskIfNeeded() throws {
        if projectLoaded { return }
        projectLoaded = true
        let root = applicationSupport.appending(component: "projects")
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let folders = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let keys = folders.compactMap { url -> String? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return nil }
            return url.lastPathComponent
        }.sorted()
        guard let key = keys.first else { return }
        let url = root.appending(component: key).appending(component: "project.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let file = try JSONDecoder().decode(ProjectFile.self, from: Data(contentsOf: url))
        project = Project(
            key: key,
            ticketTypeMapping: file.ticketTypeMapping,
            terms: file.terms
        )
    }

    private func loadInProgressDraft() throws -> Draft? {
        guard let root = draftsRoot(),
            FileManager.default.fileExists(atPath: root.path)
        else { return nil }
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
        guard let draft, let root = projectRoot() else { return }
        let folder = root.appending(component: "drafts").appending(component: draft.id)
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
        guard let draft, let root = projectRoot() else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let line = try encoder.encode(TranscriptLine(role: "user", text: field))
        guard let jsonl = String(data: line, encoding: .utf8) else { return }
        try (jsonl + "\n").write(
            to: root.appending(component: "drafts").appending(component: draft.id)
                .appending(component: "transcript.jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func draftsRoot() -> URL? {
        projectRoot()?.appending(component: "drafts")
    }

    private func projectRoot() -> URL? {
        guard let key = project?.key else { return nil }
        return applicationSupport
            .appending(component: "projects")
            .appending(component: key)
    }

    private struct ProjectFile: Codable {
        var ticketTypeMapping: [TicketType: String]
        var terms: [String]
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
        State(
            field: field,
            draft: draft,
            catalog: catalog,
            aneCompileInProgress: aneCompileInProgress,
            settings: settings,
            project: project,
            proposedProject: proposedProject,
            textMaterialWarning: textMaterialWarning
        )
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

private func decodeJSON<T: Decodable>(_ text: String) throws -> T {
    guard let value = try? JSONDecoder().decode(T.self, from: Data(text.utf8)) else {
        throw ModelFailed()
    }
    return value
}

private let writingRules = """
    Writing rules:
    Context from the Catalog and Project terms is never Scope. Never invent Scope. For a Bug, never invent the reproduction path or the cause.
    Vague Scope becomes a chat question in openQuestions, or stays blank plus the completeness marker.
    Functional, not technical, applies to Story and Bug.
    Story title: As a {Persona} I want {scope} so that {problem}. Bug title: the broken behaviour. Chore title: the action.
    Story: context paragraphs, bold nouns on first mention, related keys in prose. Bug: one-line statement of what is broken, numbered steps to reproduce, Expected against Actual, Environment. Chore: one paragraph of what and why.
    Markdown only: paragraphs, bold, bullet list, ordered list, links, one horizontal rule. No headings. No Requirements, Technical Notes, Dependencies, or Out of Scope headings.
    Definition of Done mirrors the description. It never introduces new Scope.
    """

private let generateInstruction = """
    Reply with JSON only, no tools: ticketType (story, bug, or chore), title, shortLabel, description, openQuestions.
    """

private let definitionOfDoneInstruction = """
    Reply with a JSON array of Definition of Done bullets. Read only the description. Do not add Scope. No tools.
    """

private func systemPrompt(prefix: String, instruction: String) -> String {
    [writingRules, prefix, instruction].joined(separator: "\n\n")
}

private func stuffedPrefix(catalog: Catalog, projectTerms: [String]) -> String {
    var lines = ["Catalog"]
    lines.append("Epics:")
    lines.append(
        contentsOf: catalog.epics.map { "\($0.key.value) \($0.name) \($0.status)" }
    )
    lines.append("Recent tickets:")
    lines.append(contentsOf: catalog.rows.map(catalogRowLine))
    lines.append("Components:")
    lines.append(contentsOf: catalog.componentNames)
    lines.append("Project terms:")
    lines.append(contentsOf: projectTerms)
    return lines.joined(separator: "\n")
}

private func catalogRowLine(_ row: CatalogRow) -> String {
    var parts = [row.key.value, row.title, row.jiraIssueType]
    if !row.labels.isEmpty {
        parts.append(row.labels.joined(separator: ","))
    }
    if let parent = row.parentEpicKey {
        parts.append(parent.value)
    }
    if !row.status.isEmpty {
        parts.append(row.status)
    }
    if let created = row.created {
        parts.append(iso8601(created))
    }
    if let shortLabel = row.shortLabel {
        parts.append(shortLabel)
    }
    if let ticketType = row.ticketType {
        parts.append(ticketType.rawValue)
    }
    return parts.joined(separator: " ")
}

private func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
