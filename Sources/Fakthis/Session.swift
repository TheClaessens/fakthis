import Foundation

private let catalogStaleAfter: TimeInterval = 60 * 60

public actor Session {
    public enum Intent: Sendable {
        case typeBrainDump(String)
        case attachMaterial(Material)
        case generate
        case send
        case changeTicketType(TicketType)
        case submit
        case retryUploads
        case skipFailedUploads
        case saveCredentials(Settings, jiraToken: String, modelKey: String)
        case enterProjectKey(String)
        case confirmProject(mapping: [TicketType: String])
        case dismissDuplicate
        case workOnDuplicate
        case tickRelated(TicketKey)
        case startListening
        case stopListening
        case pasteKey(String)
        case update
        case keepLiveTitle
        case refetch
        case clobber
        case nameBatch(name: String, shortLabels: [String])
        case dismissRegenerateOffer
        case focusDraft(String)
        case addDraft(shortLabel: String)
        case removeDraft(String)
        case renameSibling(id: String, shortLabel: String)
        case setDefaultEpic(TicketKey?)
        case overrideEpic(id: String, TicketKey?)
        case setBlocks([String])
        case clearBlocks
        case assignMedia(filename: String, draftIds: [String])
    }

    public enum Status: Equatable, Sendable {
        case listening
        case transcribing
        case agentThinking
        case yourTurn
    }

    public struct State: Equatable, Sendable {
        public var field: String
        public var draft: Draft?
        public var transcript: [TranscriptLine]
        public var material: [AttachedMaterial]
        public var catalog: Catalog
        public var catalogRefreshFailed: Bool
        public var aneCompileInProgress: Bool
        public var settings: Settings?
        public var project: Project?
        public var proposedProject: ProposedProject?
        public var materialWarnings: [String]
        public var failedUploads: [String]
        public var structuralWarnings: [String]
        public var duplicateInterrupt: DuplicateHit?
        public var related: [RelatedHit]
        public var status: Status
        public var rewrite: Rewrite?
        public var rewriteError: String?
        public var batch: Batch?
    }

    private var project: Project?
    private let applicationSupport: URL
    private let model: any Model
    private let jira: any Jira
    private let transcriber: any Transcriber
    private let secrets: any Secrets

    private var field = ""
    private var draft: Draft?
    private var transcript: [TranscriptLine] = []
    private var draftId: String?
    private var material: [Material] = []
    private var blockedUploads: Set<String> = []
    private var catalog = Catalog()
    private var catalogRefreshFailed = false
    private var aneCompileInProgress = true
    private var settings: Settings?
    private var proposedProject: ProposedProject?
    private var materialWarnings: [String] = []
    private var failedUploads: [String] = []
    private var duplicateInterrupt: DuplicateHit?
    private var related: [RelatedHit] = []
    private var status: Status = .yourTurn
    private var rewrite: Rewrite?
    private var rewriteError: String?
    private var fetched: RewriteTarget?
    private var batch: Batch?
    private var brainDump = ""
    private var namingTurn = ""
    private var fieldByDraft: [String: String] = [:]
    private var writtenBlocksLinks: Set<String> = []

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
        case .attachMaterial(let item):
            startBackgroundRefreshIfStale()
            try await attach(item)
        case .generate:
            try await pullCatalogIfNeverPulled()
            startBackgroundRefreshIfStale()
            try await generate()
        case .send:
            startBackgroundRefreshIfStale()
            try await send()
        case .changeTicketType(let ticketType):
            startBackgroundRefreshIfStale()
            try await changeTicketType(ticketType)
        case .submit:
            startBackgroundRefreshIfStale()
            try await submit()
        case .retryUploads:
            startBackgroundRefreshIfStale()
            try await retryUploads()
        case .skipFailedUploads:
            startBackgroundRefreshIfStale()
            try skipFailedUploads()
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
        case .dismissDuplicate:
            duplicateInterrupt = nil
            batch?.duplicates = []
        case .workOnDuplicate:
            try await workOnDuplicate()
        case .tickRelated(let key):
            tickRelated(key)
        case .startListening:
            startBackgroundRefreshIfStale()
            await startListening()
        case .stopListening:
            startBackgroundRefreshIfStale()
            try await stopListening()
        case .pasteKey(let key):
            startBackgroundRefreshIfStale()
            try await pasteKey(key)
        case .update:
            startBackgroundRefreshIfStale()
            try await update()
        case .keepLiveTitle:
            keepLiveTitle()
        case .refetch:
            startBackgroundRefreshIfStale()
            try await refetch()
        case .clobber:
            startBackgroundRefreshIfStale()
            try await clobber()
        case .nameBatch(let name, let shortLabels):
            startBackgroundRefreshIfStale()
            try nameBatch(name: name, shortLabels: shortLabels)
        case .dismissRegenerateOffer:
            batch?.offerRegenerateDraft1 = false
        case .focusDraft(let id):
            startBackgroundRefreshIfStale()
            try focusDraft(id)
        case .addDraft(let shortLabel):
            startBackgroundRefreshIfStale()
            try addDraft(shortLabel: shortLabel)
        case .removeDraft(let id):
            startBackgroundRefreshIfStale()
            try removeDraft(id)
        case .renameSibling(let id, let shortLabel):
            startBackgroundRefreshIfStale()
            try renameSibling(id: id, shortLabel: shortLabel)
        case .setDefaultEpic(let key):
            startBackgroundRefreshIfStale()
            setDefaultEpic(key)
        case .overrideEpic(let id, let key):
            startBackgroundRefreshIfStale()
            overrideEpic(id: id, key: key)
        case .setBlocks(let order):
            startBackgroundRefreshIfStale()
            setBlocks(order)
        case .clearBlocks:
            batch?.blocks = []
        case .assignMedia(let filename, let draftIds):
            startBackgroundRefreshIfStale()
            try assignMedia(filename: filename, draftIds: draftIds)
        }
        try persistBatchIfNeeded()
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
        if batch != nil {
            try refreshMatches()
            try await submitBatch()
            return
        }
        guard var draft, draft.key == nil,
            let project,
            let jiraIssueType = project.ticketTypeMapping[draft.ticketType]
        else {
            return
        }
        try refreshMatches()
        let key: TicketKey
        do {
            key = try await jira.createTicket(
                projectKey: project.key,
                title: draft.title,
                descriptionWiki: wikiMarkup(from: draft.descriptionWithOpenQuestions),
                jiraIssueType: jiraIssueType,
                parentKey: nil,
                completenessMarker: draft.openQuestions.isEmpty ? .clear : .apply
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
        await uploadPending(key: key)
        if !failedUploads.isEmpty {
            try persistDraft()
        }
    }

    private func submitBatch() async throws {
        guard var batch, let project else { return }
        try persistDraft()
        try persistMaterial()
        let order = batch.blocks.isEmpty ? batch.siblings.map(\.id) : batch.blocks
        let linking = !batch.blocks.isEmpty
        var previousKey: TicketKey?
        for id in order {
            guard let siblingIndex = batch.siblings.firstIndex(where: { $0.id == id }) else {
                continue
            }
            if let existing = batch.siblings[siblingIndex].key {
                if linking {
                    do {
                        try await writeBlocksLink(from: previousKey, to: existing)
                    } catch is JiraUnreachable {
                        self.batch = batch
                        return
                    }
                }
                try loadSibling(id)
                if draft?.id == id, draft?.key != nil {
                    await uploadPending(key: existing)
                    if !failedUploads.isEmpty {
                        try persistDraft()
                    }
                }
                previousKey = existing
                continue
            }
            try loadSibling(id)
            guard var draft, draft.key == nil, !draft.title.isEmpty,
                let jiraIssueType = project.ticketTypeMapping[draft.ticketType]
            else { continue }
            let parent = batch.siblings[siblingIndex].epicKey ?? batch.defaultEpicKey
            let key: TicketKey
            do {
                key = try await jira.createTicket(
                    projectKey: project.key,
                    title: draft.title,
                    descriptionWiki: wikiMarkup(from: draft.descriptionWithOpenQuestions),
                    jiraIssueType: jiraIssueType,
                    parentKey: parent,
                    completenessMarker: draft.openQuestions.isEmpty ? .clear : .apply
                )
            } catch is JiraUnreachable {
                self.batch = batch
                return
            }
            draft.key = key
            self.draft = draft
            batch.siblings[siblingIndex].key = key
            batch.siblings[siblingIndex].shortLabel = draft.shortLabel
            batch.siblings[siblingIndex].ticketType = draft.ticketType
            batch.siblings[siblingIndex].openQuestions = draft.openQuestions
            self.batch = batch
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
            if linking {
                do {
                    try await writeBlocksLink(from: previousKey, to: key)
                } catch is JiraUnreachable {
                    return
                }
            }
            previousKey = key
            await uploadPending(key: key)
            if !failedUploads.isEmpty {
                try persistDraft()
            }
        }
        try finishBatchIfSubmitted(batch)
    }

    private func writeBlocksLink(from previousKey: TicketKey?, to key: TicketKey) async throws {
        guard let previousKey else { return }
        let id = "\(previousKey.value)>\(key.value)"
        if writtenBlocksLinks.contains(id) { return }
        try await jira.createBlocksLink(blocker: previousKey, blocked: key)
        writtenBlocksLinks.insert(id)
    }

    private func finishBatchIfSubmitted(_ batch: Batch) throws {
        let allKeyed = batch.siblings.allSatisfy { $0.key != nil }
        guard allKeyed else { return }
        let anyFolder = batch.siblings.contains { sibling in
            guard let folder = draftsRoot()?.appending(component: sibling.id) else { return false }
            return FileManager.default.fileExists(atPath: folder.path)
        }
        guard !anyFolder else { return }
        try deleteBatchFile()
        self.batch = nil
        writtenBlocksLinks = []
    }

    private func uploadPending(key: TicketKey) async {
        failedUploads = []
        for item in material where item.isMedia && !blockedUploads.contains(item.filename) {
            do {
                try await upload(item, key: key)
            } catch {
                failedUploads.append(item.filename)
            }
        }
        try? deleteDraftFolderIfUploadsFinished()
    }

    private func upload(_ item: Material, key: TicketKey) async throws {
        try await jira.uploadAttachment(
            key: key,
            filename: item.filename,
            mimeType: item.mimeType,
            data: item.data
        )
    }

    private func retryUploads() async throws {
        guard let key = draft?.key else { return }
        var stillFailed: [String] = []
        for filename in failedUploads {
            guard let item = material.first(where: { $0.filename == filename }) else { continue }
            do {
                try await upload(item, key: key)
            } catch {
                stillFailed.append(filename)
            }
        }
        failedUploads = stillFailed
        try persistDraft()
        try deleteDraftFolderIfUploadsFinished()
    }

    private func skipFailedUploads() throws {
        guard !failedUploads.isEmpty else { return }
        failedUploads = []
        try deleteDraftFolder()
    }

    private func deleteDraftFolderIfUploadsFinished() throws {
        guard failedUploads.isEmpty else { return }
        try deleteDraftFolder()
    }

    private func deleteDraftFolder() throws {
        guard let folder = draftFolderURL(),
            FileManager.default.fileExists(atPath: folder.path)
        else { return }
        try FileManager.default.removeItem(at: folder)
    }

    private func draftFolderURL() -> URL? {
        guard let id = draft?.id ?? draftId else { return nil }
        return draftsRoot()?.appending(component: id)
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

    /// A background refresh that fails is a warning on state, never a block: Generate keeps
    /// running against the last good snapshot (§5, §9). The flag describes the snapshot in
    /// hand, so a later refresh that lands clears it.
    private func refreshCatalog() async {
        defer { refreshTask = nil }
        guard let project else { return }
        let pulled: Catalog
        do {
            pulled = try await jira.pullCatalog(projectKey: project.key)
        } catch {
            catalogRefreshFailed = true
            return
        }
        // The flag describes the snapshot in hand. The pull landed, so the snapshot is fresh
        // even if writing it to disk does not work — that is a different failure.
        catalogRefreshFailed = false
        try? applySuccessfulPull(pulled)
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

    private func attach(_ item: Material) async throws {
        guard project != nil else { return }
        if item.isMedia {
            do {
                let policy = try await jira.attachmentPolicy()
                if !policy.enabled {
                    materialWarnings.append("attachments are disabled")
                    blockedUploads.insert(item.filename)
                } else if item.data.count > policy.uploadLimit {
                    materialWarnings.append("\(item.filename) is oversize")
                    blockedUploads.insert(item.filename)
                }
            } catch {
                materialWarnings.append("could not read attachment policy")
            }
        } else if !item.isText {
            materialWarnings.append("\(item.filename) is unsupported")
            blockedUploads.insert(item.filename)
        }
        if draftId == nil {
            draftId = draft?.id ?? UUID().uuidString
        }
        material.append(item)
        try persistMaterial()
    }

    private func startListening() async {
        guard project != nil, !aneCompileInProgress, status != .listening else { return }
        status = .listening
        await transcriber.beginTake()
    }

    private func transcriberBoostList() -> [String] {
        Array(
            ((project?.terms ?? []) + catalog.epics.map(\.name) + catalog.componentNames)
                .prefix(TranscriberBoost.cap)
        )
    }

    private func stopListening() async throws {
        guard status == .listening else { return }
        status = .transcribing
        defer { status = .yourTurn }
        do {
            commitTake(try await transcriber.transcribe(boostList: transcriberBoostList()))
        } catch is TranscribeFailed {
            return
        }
    }

    private func commitTake(_ take: String) {
        if rewrite != nil {
            field = take
            return
        }
        if let draft, draft.key == nil, !draft.title.isEmpty || !draft.description.isEmpty {
            field = take
            return
        }
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        field = trimmed.isEmpty ? take : trimmed + " " + take
    }

    private var isUploadQueue: Bool {
        draft?.key != nil && rewrite == nil
    }

    private func update() async throws {
        guard let live = try await liveForWrite() else { return }
        if let fetched, live.updated > fetched.updated {
            var rewrite = rewrite
            rewrite?.stale = true
            self.rewrite = rewrite
            return
        }
        try await putRewrite(live)
    }

    private func clobber() async throws {
        guard let live = try await liveForWrite() else { return }
        try await putRewrite(live)
    }

    private func liveForWrite() async throws -> RewriteTarget? {
        guard let key = draft?.key, rewrite != nil else { return nil }
        do {
            return try await jira.fetchRewriteTarget(key: key)
        } catch is JiraUnreachable {
            return nil
        } catch is JiraHTTPError {
            return nil
        }
    }

    private func putRewrite(_ live: RewriteTarget) async throws {
        guard let draft, let key = draft.key else { return }
        do {
            try await jira.updateTicket(
                key: key,
                title: draft.title,
                descriptionWiki: wikiMarkup(from: draft.descriptionWithOpenQuestions),
                completenessMarker: draft.openQuestions.isEmpty ? .clear : .apply
            )
        } catch is JiraUnreachable {
            return
        }
        fetched = live
        rewrite = nil
        upsertCatalogRow(for: draft, key: key, jiraIssueType: live.jiraIssueType)
        try persistDraft()
        try persistCatalog()
        await uploadPending(key: key)
        if !failedUploads.isEmpty {
            try persistDraft()
        }
    }

    private func upsertCatalogRow(for draft: Draft, key: TicketKey, jiraIssueType: String) {
        if let index = catalog.rows.firstIndex(where: { $0.key == key }) {
            catalog.rows[index].title = draft.title
            catalog.rows[index].shortLabel = draft.shortLabel
            catalog.rows[index].ticketType = draft.ticketType
            return
        }
        catalog.rows.append(
            CatalogRow(
                key: key,
                title: draft.title,
                jiraIssueType: jiraIssueType,
                shortLabel: draft.shortLabel,
                ticketType: draft.ticketType
            )
        )
    }

    private func refetch() async throws {
        guard let key = draft?.key, rewrite != nil else { return }
        let target: RewriteTarget
        do {
            target = try await jira.fetchRewriteTarget(key: key)
        } catch is JiraUnreachable {
            return
        } catch is JiraHTTPError {
            return
        }
        showLive(target)
        replaceLiveMaterial()
        try persistDraft()
        try persistMaterial()
    }

    private func generate() async throws {
        if isUploadQueue { return }
        guard project != nil else { return }
        if rewrite == nil, brainDump.isEmpty {
            brainDump = field
        }
        try await reviseDraft(
            user: generateUserMessage(),
            instruction: rewrite == nil ? generateInstruction : rewriteInstruction(),
            screenshots: material.filter(\.isScreenshot)
        )
    }

    private func rewriteInstruction() -> String {
        guard let jiraType = fetched?.jiraIssueType,
            let mapping = project?.ticketTypeMapping
        else { return rewriteGenerateInstruction }
        let matches = mapping.filter { $0.value == jiraType }
        guard matches.count == 1, let ticketType = matches.first?.key else {
            return rewriteGenerateInstruction
        }
        return """
            \(rewriteGenerateInstruction)
            Jira issue type \(jiraType) maps 1:1 to \(ticketType.rawValue).
            """
    }

    private func generateUserMessage() -> String {
        let blocks = textMaterialBlocks() + relatedContextBlocks() + batchContextBlocks()
        let user: String
        if let draft, draft.title.isEmpty, draft.description.isEmpty, !brainDump.isEmpty {
            var parts = [brainDump]
            if !namingTurn.isEmpty, namingTurn != brainDump {
                parts.append(namingTurn)
            }
            user = parts.joined(separator: "\n\n")
        } else {
            user = field
        }
        guard !blocks.isEmpty else { return user }
        return ([user] + blocks).joined(separator: "\n\n")
    }

    private func batchContextBlocks() -> [String] {
        guard let batch,
            let index = batch.siblings.firstIndex(where: { $0.id == batch.focusedDraftId })
        else { return [] }
        let list = batch.siblings.enumerated().map { position, sibling in
            if let ticketType = sibling.ticketType {
                return "\(position + 1). \(sibling.shortLabel) (\(ticketType.rawValue))"
            }
            return "\(position + 1). \(sibling.shortLabel)"
        }.joined(separator: "\n")
        return [
            """
            You are Draft \(index + 1) of \(batch.siblings.count). Write this one.
            Siblings:
            \(list)
            """
        ]
    }

    private func send() async throws {
        guard let draft, !isUploadQueue, project != nil else { return }
        try await reviseDraft(
            user: draftAndAnswerMessage(draft),
            instruction: sendInstruction,
            screenshots: []
        )
    }

    private func changeTicketType(_ ticketType: TicketType) async throws {
        guard let draft, !isUploadQueue, project != nil else { return }
        try await reviseDraft(
            user: reshapeUserMessage(draft),
            instruction: reshapeInstruction(ticketType),
            screenshots: material.filter(\.isScreenshot),
            ticketType: ticketType
        )
    }

    private func draftAndAnswerMessage(_ draft: Draft) -> String {
        let base = """
            Chat answer:
            \(field)

            \(currentDraftBlock(draft))
            """
        let extra = relatedContextBlocks() + batchContextBlocks()
        guard !extra.isEmpty else { return base }
        return ([base] + extra).joined(separator: "\n\n")
    }

    private func reshapeUserMessage(_ draft: Draft) -> String {
        ([currentDraftBlock(draft), field] + textMaterialBlocks() + relatedContextBlocks()
            + batchContextBlocks())
            .joined(separator: "\n\n")
    }

    private func currentDraftBlock(_ draft: Draft) -> String {
        """
        Current title: \(draft.title)
        Current short label: \(draft.shortLabel)
        Current description:
        \(draft.description)
        Open questions:
        \(draft.openQuestions.joined(separator: "\n"))
        """
    }

    private func textMaterialBlocks() -> [String] {
        textMaterialForGenerate().map { item in
            let body = String(data: item.data, encoding: .utf8) ?? ""
            return "\(item.filename)\n\(body)"
        }
    }

    private func textMaterialForGenerate() -> [Material] {
        var seen = Set<String>()
        var items: [Material] = []
        func add(_ item: Material) {
            guard item.isText, seen.insert(item.filename).inserted else { return }
            items.append(item)
        }
        if let batch {
            for sibling in batch.siblings {
                for item in materialOnDisk(draftId: sibling.id) { add(item) }
            }
        }
        for item in material { add(item) }
        return items
    }

    private func materialOnDisk(draftId: String) -> [Material] {
        guard let folder = draftsRoot()?.appending(component: draftId)
            .appending(component: "material")
        else { return [] }
        let indexURL = folder.appending(component: "index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path),
            let records = try? JSONDecoder().decode(
                [MaterialRecord].self,
                from: Data(contentsOf: indexURL)
            )
        else { return [] }
        return records.compactMap { record in
            let url = folder.appending(component: record.filename)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return Material(filename: record.filename, mimeType: record.mimeType, data: data)
        }
    }

    private func relatedContextBlocks() -> [String] {
        let keys = related.filter(\.ticked).map(\.key.value)
        guard !keys.isEmpty else { return [] }
        return ["Related: \(keys.joined(separator: ", "))"]
    }

    private func tickRelated(_ key: TicketKey) {
        guard let index = related.firstIndex(where: { $0.key == key }) else { return }
        related[index].ticked.toggle()
    }

    private func pasteKey(_ raw: String) async throws {
        guard let project else { return }
        rewriteError = nil
        let key = TicketKey(raw)
        if !key.value.hasPrefix("\(project.key)-") {
            rewriteError = "\(key.value) is not in this Project"
            return
        }
        let target: RewriteTarget
        do {
            target = try await jira.fetchRewriteTarget(key: key)
        } catch is JiraUnreachable {
            return
        } catch let error as JiraHTTPError where error.statusCode == 404 {
            rewriteError = "\(key.value) was not found"
            return
        } catch is JiraHTTPError {
            return
        }
        if target.jiraIssueType.compare("Epic", options: .caseInsensitive) == .orderedSame {
            rewriteError = "\(key.value) is an epic"
            return
        }
        showLive(target)
        material = liveMaterial()
        transcript = []
        let id = UUID().uuidString
        draftId = id
        draft = Draft(
            id: id,
            ticketType: .story,
            title: "",
            shortLabel: "",
            description: "",
            openQuestions: [],
            key: key
        )
        try persistDraft()
        try persistMaterial()
    }

    private func showLive(_ target: RewriteTarget) {
        fetched = target
        let comments = Array(target.comments.prefix(50))
        rewrite = Rewrite(
            liveTitle: target.title,
            liveDescription: target.description,
            comments: comments,
            commentsTruncated: target.comments.count > 50,
            watchersNote: "Watchers of \(target.key.value) are emailed",
            stale: false
        )
    }

    private func replaceLiveMaterial() {
        let live = liveMaterial()
        material.removeAll {
            $0.filename == "live-description.md" || $0.filename == "comments.md"
        }
        material.insert(contentsOf: live, at: 0)
    }

    private func liveMaterial() -> [Material] {
        guard let rewrite else { return [] }
        var items = [
            Material(
                filename: "live-description.md",
                mimeType: "text/plain",
                data: Data(rewrite.liveDescription.utf8)
            )
        ]
        if !rewrite.comments.isEmpty {
            items.append(
                Material(
                    filename: "comments.md",
                    mimeType: "text/plain",
                    data: Data(rewrite.comments.joined(separator: "\n").utf8)
                )
            )
        }
        return items
    }

    private func keepLiveTitle() {
        guard var draft, let rewrite else { return }
        draft.title = rewrite.liveTitle
        self.draft = draft
    }

    private func focusDraft(_ id: String) throws {
        guard var batch, batch.siblings.contains(where: { $0.id == id }) else { return }
        try persistDraft()
        try persistMaterial()
        if let current = draftId {
            fieldByDraft[current] = field
        }
        batch.focusedDraftId = id
        self.batch = batch
        try loadSibling(id)
        field = fieldByDraft[id] ?? ""
    }

    private func addDraft(shortLabel: String) throws {
        guard var batch, project != nil, rewrite == nil else { return }
        let focused = draft
        let focusedId = draftId
        let id = UUID().uuidString
        draft = Draft(
            id: id,
            ticketType: .story,
            title: "",
            shortLabel: shortLabel,
            description: "",
            openQuestions: []
        )
        draftId = id
        try persistDraft()
        batch.siblings.append(BatchSibling(id: id, shortLabel: shortLabel))
        if !batch.blocks.isEmpty {
            batch.blocks.append(id)
        }
        draft = focused
        draftId = focusedId
        self.batch = batch
    }

    private func removeDraft(_ id: String) throws {
        guard var batch, batch.siblings.contains(where: { $0.id == id }) else { return }
        let remaining = batch.siblings.filter { $0.id != id }
        if let folder = draftsRoot()?.appending(component: id),
            FileManager.default.fileExists(atPath: folder.path)
        {
            try FileManager.default.removeItem(at: folder)
        }
        fieldByDraft[id] = nil
        if remaining.count < 2 {
            try deleteBatchFile()
            self.batch = nil
            if let keep = remaining.first {
                try loadSibling(keep.id)
            }
            return
        }
        batch.siblings = remaining
        batch.blocks.removeAll { $0 == id }
        if draftId == id, let keep = remaining.first {
            batch.focusedDraftId = keep.id
            self.batch = batch
            try loadSibling(keep.id)
            return
        }
        self.batch = batch
    }

    private func loadSibling(_ id: String) throws {
        guard let folder = draftsRoot()?.appending(component: id),
            let stored = try storedDraft(in: folder)
        else { return }
        draft = stored.draft
        draftId = stored.draft.id
        failedUploads = stored.failedUploads
        blockedUploads = []
        material = try loadMaterial()
        loadTranscript(draftId: id)
        field = fieldByDraft[id] ?? field
    }

    private func renameSibling(id: String, shortLabel: String) throws {
        guard var batch, let index = batch.siblings.firstIndex(where: { $0.id == id }) else {
            return
        }
        batch.siblings[index].shortLabel = shortLabel
        self.batch = batch
        if draft?.id == id {
            draft?.shortLabel = shortLabel
            try persistDraft()
        }
    }

    private func setDefaultEpic(_ key: TicketKey?) {
        guard var batch else { return }
        if let key, !catalog.epics.contains(where: { $0.key == key }) {
            return
        }
        batch.defaultEpicKey = key
        self.batch = batch
    }

    private func overrideEpic(id: String, key: TicketKey?) {
        guard var batch, let index = batch.siblings.firstIndex(where: { $0.id == id }) else {
            return
        }
        if let key, !catalog.epics.contains(where: { $0.key == key }) {
            return
        }
        batch.siblings[index].epicKey = key
        self.batch = batch
    }

    private func setBlocks(_ order: [String]) {
        guard var batch else { return }
        let siblingIds = Set(batch.siblings.map(\.id))
        guard Set(order) == siblingIds else { return }
        batch.blocks = order
        self.batch = batch
    }

    private func assignMedia(filename: String, draftIds: [String]) throws {
        guard let batch else { return }
        let allowed = Set(batch.siblings.map(\.id))
        let targets = draftIds.filter { allowed.contains($0) }
        guard let item = findMaterial(filename) else { return }
        try persistMaterial()
        for id in targets {
            try writeMaterial(item, toDraft: id)
        }
        if let focused = draftId, targets.contains(focused),
            !material.contains(where: { $0.filename == filename })
        {
            material.append(item)
        }
    }

    private func findMaterial(_ filename: String) -> Material? {
        if let item = material.first(where: { $0.filename == filename }) { return item }
        guard let batch else { return nil }
        for sibling in batch.siblings {
            if let item = materialOnDisk(draftId: sibling.id).first(where: { $0.filename == filename })
            {
                return item
            }
        }
        return nil
    }

    private func writeMaterial(_ item: Material, toDraft id: String) throws {
        guard let folder = draftsRoot()?.appending(component: id) else { return }
        let materialFolder = folder.appending(component: "material")
        try FileManager.default.createDirectory(
            at: materialFolder,
            withIntermediateDirectories: true
        )
        try item.data.write(to: materialFolder.appending(component: item.filename))
        var records = materialOnDisk(draftId: id).map {
            MaterialRecord(
                filename: $0.filename,
                mimeType: $0.mimeType,
                blockedFromUpload: blockedUploads.contains($0.filename)
            )
        }
        if !records.contains(where: { $0.filename == item.filename }) {
            records.append(
                MaterialRecord(
                    filename: item.filename,
                    mimeType: item.mimeType,
                    blockedFromUpload: blockedUploads.contains(item.filename)
                )
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: materialFolder.appending(component: "index.json"))
    }

    private func nameBatch(name: String, shortLabels: [String]) throws {
        guard project != nil, rewrite == nil, draft?.key == nil, batch == nil, shortLabels.count >= 2
        else {
            return
        }
        let converting = draft.map { !$0.title.isEmpty || !$0.description.isEmpty } ?? false
        if converting {
            namingTurn = field
        }
        let firstId = draft?.id ?? draftId ?? UUID().uuidString
        var first = draft
            ?? Draft(
                id: firstId,
                ticketType: .story,
                title: "",
                shortLabel: shortLabels[0],
                description: "",
                openQuestions: []
            )
        first.shortLabel = shortLabels[0]
        draft = first
        draftId = firstId
        try persistDraft()
        try persistMaterial()

        var siblings = [
            BatchSibling(
                id: firstId,
                shortLabel: first.shortLabel,
                ticketType: converting ? first.ticketType : nil,
                openQuestions: first.openQuestions
            )
        ]
        for label in shortLabels.dropFirst() {
            let id = UUID().uuidString
            draft = Draft(
                id: id,
                ticketType: .story,
                title: "",
                shortLabel: label,
                description: "",
                openQuestions: []
            )
            draftId = id
            try persistDraft()
            siblings.append(BatchSibling(id: id, shortLabel: label))
        }

        draft = first
        draftId = firstId
        batch = Batch(
            name: name,
            siblings: siblings,
            focusedDraftId: firstId,
            blocks: siblings.map(\.id),
            offerRegenerateDraft1: converting
        )
    }

    private func workOnDuplicate() async throws {
        switch duplicateInterrupt {
        case .catalog(let key, _, _):
            duplicateInterrupt = nil
            try await pasteKey(key.value)
        case .localDraft(let id, _, _):
            guard let folder = draftsRoot()?.appending(component: id),
                let stored = try storedDraft(in: folder)
            else { return }
            draft = stored.draft
            draftId = stored.draft.id
            failedUploads = stored.failedUploads
            blockedUploads = []
            material = try loadMaterial()
            try refreshMatches()
            duplicateInterrupt = nil
        case nil:
            return
        }
    }

    private func reviseDraft(
        user: String,
        instruction: String,
        screenshots: [Material],
        ticketType: TicketType? = nil
    ) async throws {
        guard let project else { return }
        status = .agentThinking
        defer { status = .yourTurn }
        let generated: GenerateReply
        let done: [String]
        do {
            let prefix = stuffedPrefix(catalog: catalog, projectTerms: project.terms)
            generated = try decodeJSON(
                try await model.complete(
                    system: systemPrompt(prefix: prefix, instruction: instruction),
                    user: user,
                    screenshots: screenshots
                )
            )
            done = try decodeJSON(
                try await model.complete(
                    system: systemPrompt(
                        prefix: prefix,
                        instruction: definitionOfDoneInstruction
                    ),
                    user: generated.description,
                    screenshots: []
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
        let id = draft?.id ?? draftId ?? UUID().uuidString
        draftId = id
        draft = Draft(
            id: id,
            ticketType: ticketType ?? generated.ticketType,
            title: generated.title,
            shortLabel: generated.shortLabel,
            description: description,
            openQuestions: generated.openQuestions,
            key: draft?.key
        )
        try persistDraft()
        try persistMaterial()
        try recordTurn(said: field, asked: generated.openQuestions)
        refreshBatchSiblings()
        try refreshMatches()
    }

    private func refreshBatchSiblings() {
        guard var batch, let draft else { return }
        if let index = batch.siblings.firstIndex(where: { $0.id == draft.id }) {
            batch.siblings[index].shortLabel = draft.shortLabel
            batch.siblings[index].ticketType = draft.ticketType
            batch.siblings[index].key = draft.key
            batch.siblings[index].openQuestions = draft.openQuestions
            if index == 0 {
                batch.offerRegenerateDraft1 = false
            }
        }
        self.batch = batch
    }

    private func refreshMatches() throws {
        let ticked = Set(related.filter(\.ticked).map(\.key))
        duplicateInterrupt = nil
        related = []
        guard let draft else { return }

        var bestDuplicate: (score: Double, hit: DuplicateHit)?
        var relatedCandidates: [(score: Double, hit: RelatedHit)] = []

        func considerDuplicate(score: Double, hit: DuplicateHit) {
            if let current = bestDuplicate, score <= current.score { return }
            bestDuplicate = (score, hit)
        }

        for row in catalog.rows {
            if row.key == draft.key { continue }
            let compared = row.shortLabel ?? row.title
            let against = row.shortLabel != nil ? draft.shortLabel : draft.title
            let tokens = matchTokens(against)
            let other = matchTokens(compared)
            let intersection = tokens.intersection(other).count
            guard intersection >= 1 else { continue }
            let score = overlapCoefficient(intersection, min(tokens.count, other.count))

            relatedCandidates.append(
                (
                    score,
                    RelatedHit(key: row.key, title: row.title, ticked: ticked.contains(row.key))
                )
            )
            let done = row.status.compare("Done", options: .caseInsensitive) == .orderedSame
            if !done,
                typeAllowsDuplicate(row, draft: draft),
                isDuplicateScore(score, intersection: intersection, against: against, compared: compared)
            {
                considerDuplicate(
                    score: score,
                    hit: .catalog(key: row.key, shortLabel: row.shortLabel, title: row.title)
                )
            }
        }

        for local in try localCreateDrafts() where local.id != draft.id {
            if batch?.siblings.contains(where: { $0.id == local.id }) == true { continue }
            let tokens = matchTokens(draft.shortLabel)
            let other = matchTokens(local.shortLabel)
            let intersection = tokens.intersection(other).count
            let score = overlapCoefficient(intersection, min(tokens.count, other.count))
            guard local.ticketType == draft.ticketType,
                isDuplicateScore(
                    score,
                    intersection: intersection,
                    against: draft.shortLabel,
                    compared: local.shortLabel
                )
            else { continue }
            considerDuplicate(
                score: score,
                hit: .localDraft(id: local.id, shortLabel: local.shortLabel, title: local.title)
            )
        }

        duplicateInterrupt = bestDuplicate?.hit
        related = relatedCandidates
            .filter { $0.hit.key != bestDuplicate?.hit.key }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.hit.key.value < rhs.hit.key.value
            }
            .prefix(3)
            .map(\.hit)
        if batch != nil {
            duplicateInterrupt = nil
            try refreshBatchDuplicates()
        }
    }

    private func refreshBatchDuplicates() throws {
        guard var batch else { return }
        let siblingIds = Set(batch.siblings.map(\.id))
        var hits: [BatchDuplicate] = []
        for sibling in batch.siblings {
            let candidate: Draft
            if sibling.id == draft?.id, let draft {
                candidate = draft
            } else if let folder = draftsRoot()?.appending(component: sibling.id),
                let stored = try storedDraft(in: folder)
            {
                candidate = stored.draft
            } else {
                continue
            }
            guard !candidate.title.isEmpty else { continue }
            let hit: DuplicateHit?
            if let catalogHit = catalogDuplicate(for: candidate) {
                hit = catalogHit
            } else {
                hit = try localDuplicate(for: candidate, excluding: siblingIds)
            }
            guard let hit else { continue }
            hits.append(
                BatchDuplicate(
                    draftId: candidate.id,
                    shortLabel: candidate.shortLabel,
                    hit: hit
                )
            )
        }
        batch.duplicates = hits
        self.batch = batch
    }

    private func catalogDuplicate(for draft: Draft) -> DuplicateHit? {
        var best: (score: Double, hit: DuplicateHit)?
        for row in catalog.rows {
            if row.key == draft.key { continue }
            let compared = row.shortLabel ?? row.title
            let against = row.shortLabel != nil ? draft.shortLabel : draft.title
            let tokens = matchTokens(against)
            let other = matchTokens(compared)
            let intersection = tokens.intersection(other).count
            guard intersection >= 1 else { continue }
            let score = overlapCoefficient(intersection, min(tokens.count, other.count))
            let done = row.status.compare("Done", options: .caseInsensitive) == .orderedSame
            if !done,
                typeAllowsDuplicate(row, draft: draft),
                isDuplicateScore(
                    score,
                    intersection: intersection,
                    against: against,
                    compared: compared
                )
            {
                if let current = best, score <= current.score { continue }
                best = (
                    score,
                    .catalog(key: row.key, shortLabel: row.shortLabel, title: row.title)
                )
            }
        }
        return best?.hit
    }

    private func localDuplicate(for draft: Draft, excluding siblingIds: Set<String>) throws -> DuplicateHit? {
        var best: (score: Double, hit: DuplicateHit)?
        for local in try localCreateDrafts() where local.id != draft.id && !siblingIds.contains(local.id) {
            let tokens = matchTokens(draft.shortLabel)
            let other = matchTokens(local.shortLabel)
            let intersection = tokens.intersection(other).count
            let score = overlapCoefficient(intersection, min(tokens.count, other.count))
            guard local.ticketType == draft.ticketType,
                isDuplicateScore(
                    score,
                    intersection: intersection,
                    against: draft.shortLabel,
                    compared: local.shortLabel
                )
            else { continue }
            if let current = best, score <= current.score { continue }
            best = (
                score,
                .localDraft(id: local.id, shortLabel: local.shortLabel, title: local.title)
            )
        }
        return best?.hit
    }

    private func typeAllowsDuplicate(_ row: CatalogRow, draft: Draft) -> Bool {
        if let ticketType = row.ticketType {
            return ticketType == draft.ticketType
        }
        guard let mapping = project?.ticketTypeMapping else { return true }
        let unique = Set(mapping.values)
        if unique.count < mapping.count { return true }
        guard let inferred = mapping.first(where: { $0.value == row.jiraIssueType })?.key
        else { return true }
        return inferred == draft.ticketType
    }

    private func loadDraftIfMissing() throws {
        if draft != nil { return }
        guard project != nil else { return }
        try loadBatchIfNeeded()
        if draft != nil { return }
        if let stored = try loadStoredDraft() {
            draft = stored.draft
            draftId = stored.draft.id
            material = try loadMaterial()
            failedUploads = stored.failedUploads
            rewrite = stored.rewrite
            fetched = stored.fetched
            loadTranscript(draftId: stored.draft.id)
            return
        }
        try loadPendingMaterial()
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

    private func loadStoredDraft() throws -> StoredDraft? {
        guard let root = draftsRoot(),
            FileManager.default.fileExists(atPath: root.path)
        else { return nil }
        let folders = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var rewriting: StoredDraft?
        var create: StoredDraft?
        var queue: StoredDraft?
        for folder in folders {
            guard let stored = try storedDraft(in: folder) else { continue }
            if stored.rewrite != nil {
                if rewriting == nil { rewriting = stored }
            } else if stored.draft.key == nil {
                if create == nil { create = stored }
            } else if queue == nil {
                queue = stored
            }
        }
        return rewriting ?? create ?? queue
    }

    private func localCreateDrafts() throws -> [Draft] {
        guard let root = draftsRoot(),
            FileManager.default.fileExists(atPath: root.path)
        else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try folders.compactMap { folder in
            guard let stored = try storedDraft(in: folder), stored.draft.key == nil else {
                return nil
            }
            return stored.draft
        }
    }

    private func storedDraft(in folder: URL) throws -> StoredDraft? {
        guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { return nil }
        let sidecarURL = folder.appending(component: "draft.json")
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return nil }
        let sidecar = try JSONDecoder().decode(Sidecar.self, from: Data(contentsOf: sidecarURL))
        let description = try String(
            contentsOf: folder.appending(component: "description.md"),
            encoding: .utf8
        )
        return StoredDraft(
            draft: Draft(
                id: folder.lastPathComponent,
                ticketType: sidecar.ticketType,
                title: sidecar.title,
                shortLabel: sidecar.shortLabel,
                description: description,
                openQuestions: sidecar.openQuestions,
                key: sidecar.key.map(TicketKey.init)
            ),
            failedUploads: sidecar.failedUploads,
            rewrite: sidecar.rewrite,
            fetched: sidecar.fetched
        )
    }

    private func loadPendingMaterial() throws {
        guard material.isEmpty, let root = draftsRoot(),
            FileManager.default.fileExists(atPath: root.path)
        else { return }
        let folders = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            if FileManager.default.fileExists(
                atPath: folder.appending(component: "draft.json").path
            ) {
                continue
            }
            draftId = folder.lastPathComponent
            material = try loadMaterial()
            if !material.isEmpty { return }
            draftId = nil
        }
    }

    private func persistMaterial() throws {
        guard let folder = draftFolderURL(), !material.isEmpty else { return }
        let materialFolder = folder.appending(component: "material")
        try FileManager.default.createDirectory(
            at: materialFolder,
            withIntermediateDirectories: true
        )
        for item in material {
            try item.data.write(to: materialFolder.appending(component: item.filename))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let index = material.map {
            MaterialRecord(
                filename: $0.filename,
                mimeType: $0.mimeType,
                blockedFromUpload: blockedUploads.contains($0.filename)
            )
        }
        try encoder.encode(index).write(to: materialFolder.appending(component: "index.json"))
    }

    private func loadMaterial() throws -> [Material] {
        guard let folder = draftFolderURL() else { return [] }
        let materialFolder = folder.appending(component: "material")
        let indexURL = materialFolder.appending(component: "index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let records = try JSONDecoder().decode(
            [MaterialRecord].self,
            from: Data(contentsOf: indexURL)
        )
        return try records.map { record in
            if record.blockedFromUpload {
                blockedUploads.insert(record.filename)
            }
            return Material(
                filename: record.filename,
                mimeType: record.mimeType,
                data: try Data(contentsOf: materialFolder.appending(component: record.filename))
            )
        }
    }

    private func persistBatchIfNeeded() throws {
        guard let batch, let root = projectRoot() else { return }
        let folder = root.appending(component: "batches")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var epicOverrides: [String: String] = [:]
        for sibling in batch.siblings {
            if let epic = sibling.epicKey {
                epicOverrides[sibling.id] = epic.value
            }
        }
        let file = BatchFile(
            name: batch.name,
            draftIds: batch.siblings.map(\.id),
            focusedDraftId: batch.focusedDraftId,
            blocks: batch.blocks,
            defaultEpicKey: batch.defaultEpicKey?.value,
            epicOverrides: epicOverrides,
            offerRegenerateDraft1: batch.offerRegenerateDraft1,
            brainDump: brainDump,
            namingTurn: namingTurn,
            keys: Dictionary(
                uniqueKeysWithValues: batch.siblings.compactMap { sibling in
                    sibling.key.map { (sibling.id, $0.value) }
                }
            ),
            writtenBlocksLinks: writtenBlocksLinks.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(file).write(
            to: folder.appending(component: "\(batch.id).json")
        )
    }

    private func deleteBatchFile() throws {
        guard let batch, let folder = projectRoot()?.appending(component: "batches") else {
            return
        }
        let url = folder.appending(component: "\(batch.id).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private var batchLoaded = false

    private func loadBatchIfNeeded() throws {
        if batchLoaded { return }
        batchLoaded = true
        guard let folder = projectRoot()?.appending(component: "batches"),
            FileManager.default.fileExists(atPath: folder.path)
        else { return }
        let files = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        guard let url = files.first, let drafts = draftsRoot() else { return }
        let file = try JSONDecoder().decode(BatchFile.self, from: Data(contentsOf: url))
        brainDump = file.brainDump
        namingTurn = file.namingTurn
        writtenBlocksLinks = Set(file.writtenBlocksLinks)
        var siblings: [BatchSibling] = []
        for id in file.draftIds {
            let stored = try storedDraft(in: drafts.appending(component: id))
            siblings.append(
                BatchSibling(
                    id: id,
                    shortLabel: stored?.draft.shortLabel ?? "",
                    epicKey: file.epicOverrides[id].map(TicketKey.init),
                    ticketType: stored.flatMap { $0.draft.title.isEmpty ? nil : $0.draft.ticketType },
                    key: file.keys[id].map(TicketKey.init) ?? stored?.draft.key,
                    openQuestions: stored?.draft.openQuestions ?? []
                )
            )
        }
        batch = Batch(
            name: file.name,
            siblings: siblings,
            focusedDraftId: file.focusedDraftId,
            blocks: file.blocks,
            offerRegenerateDraft1: file.offerRegenerateDraft1,
            defaultEpicKey: file.defaultEpicKey.map(TicketKey.init),
            id: url.deletingPathExtension().lastPathComponent
        )
        try loadSibling(file.focusedDraftId)
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
            key: draft.key?.value,
            failedUploads: failedUploads,
            rewrite: rewrite,
            fetched: fetched
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

    /// Both sides of one press: what the PM said, then what the agent asked back. The agent's
    /// turn is its open questions — those are the only thing it says to the PM; everything else
    /// it produces is the Draft, which the window already shows.
    ///
    /// One line per question, so the window renders them as the separate things they are. The
    /// agent hands back its whole open list every press, so a question the PM has not answered
    /// comes back unchanged: asking it again is the model repeating itself, not a new turn.
    private func recordTurn(said: String, asked: [String]) throws {
        if !said.isEmpty {
            transcript.append(TranscriptLine(role: .pm, text: said))
        }
        let alreadyAsked = Set(transcript.filter { $0.role == .agent }.map(\.text))
        for question in asked where !alreadyAsked.contains(question) {
            transcript.append(TranscriptLine(role: .agent, text: question))
        }
        try persistTranscript()
    }

    private func transcriptURL(draftId: String) -> URL? {
        draftsRoot()?.appending(component: draftId).appending(component: "transcript.jsonl")
    }

    private func persistTranscript() throws {
        guard let draft, let url = transcriptURL(draftId: draft.id) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let jsonl = try transcript.map { line in
            String(decoding: try encoder.encode(line), as: UTF8.self)
        }
        try (jsonl.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Replaces the conversation rather than adding to it: the transcript on screen is always
    /// the focused Draft's, and a Draft with no chat yet has an empty one.
    private func loadTranscript(draftId: String) {
        transcript = []
        guard let url = transcriptURL(draftId: draftId),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        let decoder = JSONDecoder()
        transcript = text.split(separator: "\n").compactMap {
            try? decoder.decode(TranscriptLine.self, from: Data($0.utf8))
        }
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

    private struct StoredDraft {
        var draft: Draft
        var failedUploads: [String]
        var rewrite: Rewrite?
        var fetched: RewriteTarget?
    }

    private struct MaterialRecord: Codable {
        var filename: String
        var mimeType: String
        var blockedFromUpload: Bool

        enum CodingKeys: String, CodingKey {
            case filename, mimeType, blockedFromUpload
        }

        init(filename: String, mimeType: String, blockedFromUpload: Bool) {
            self.filename = filename
            self.mimeType = mimeType
            self.blockedFromUpload = blockedFromUpload
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            filename = try container.decode(String.self, forKey: .filename)
            mimeType = try container.decode(String.self, forKey: .mimeType)
            blockedFromUpload =
                try container.decodeIfPresent(Bool.self, forKey: .blockedFromUpload) ?? false
        }
    }

    private struct Sidecar: Codable {
        var ticketType: TicketType
        var title: String
        var shortLabel: String
        var openQuestions: [String]
        var key: String?
        var failedUploads: [String]
        var rewrite: Rewrite?
        var fetched: RewriteTarget?

        enum CodingKeys: String, CodingKey {
            case ticketType, title, shortLabel, openQuestions, key, failedUploads
            case rewrite, fetched
        }

        init(
            ticketType: TicketType,
            title: String,
            shortLabel: String,
            openQuestions: [String],
            key: String?,
            failedUploads: [String],
            rewrite: Rewrite?,
            fetched: RewriteTarget?
        ) {
            self.ticketType = ticketType
            self.title = title
            self.shortLabel = shortLabel
            self.openQuestions = openQuestions
            self.key = key
            self.failedUploads = failedUploads
            self.rewrite = rewrite
            self.fetched = fetched
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ticketType = try container.decode(TicketType.self, forKey: .ticketType)
            title = try container.decode(String.self, forKey: .title)
            shortLabel = try container.decode(String.self, forKey: .shortLabel)
            openQuestions = try container.decode([String].self, forKey: .openQuestions)
            key = try container.decodeIfPresent(String.self, forKey: .key)
            failedUploads = try container.decodeIfPresent([String].self, forKey: .failedUploads) ?? []
            rewrite = try container.decodeIfPresent(Rewrite.self, forKey: .rewrite)
            fetched = try container.decodeIfPresent(RewriteTarget.self, forKey: .fetched)
        }
    }

    private struct BatchFile: Codable {
        var name: String
        var draftIds: [String]
        var focusedDraftId: String
        var blocks: [String]
        var defaultEpicKey: String?
        var epicOverrides: [String: String]
        var offerRegenerateDraft1: Bool
        var brainDump: String
        var namingTurn: String
        var keys: [String: String]
        var writtenBlocksLinks: [String]
    }

    private func structuralWarningsForSnapshot() -> [String] {
        guard let draft, !draft.title.isEmpty || !draft.description.isEmpty else { return [] }
        return structuralWarnings(for: draft)
    }

    private func snapshot() -> State {
        State(
            field: field,
            draft: draft,
            transcript: transcript,
            material: material.map(\.attached),
            catalog: catalog,
            catalogRefreshFailed: catalogRefreshFailed,
            aneCompileInProgress: aneCompileInProgress,
            settings: settings,
            project: project,
            proposedProject: proposedProject,
            materialWarnings: materialWarnings,
            failedUploads: failedUploads,
            structuralWarnings: structuralWarningsForSnapshot(),
            duplicateInterrupt: duplicateInterrupt,
            related: related,
            status: status,
            rewrite: rewrite,
            rewriteError: rewriteError,
            batch: batch
        )
    }
}

private func structuralWarnings(for draft: Draft) -> [String] {
    titleConventionWarnings(draft) + typeShapeWarnings(draft) + descriptionWarnings(draft.description)
}

private func titleConventionWarnings(_ draft: Draft) -> [String] {
    switch draft.ticketType {
    case .story:
        draft.title.hasPrefix("As a ")
            ? [] : ["title does not match the Story convention"]
    case .bug:
        isPersonaOrBlankTitle(draft.title)
            ? ["title does not match the Bug convention"] : []
    case .chore:
        isPersonaOrBlankTitle(draft.title)
            ? ["title does not match the Chore convention"] : []
    }
}

private func isPersonaOrBlankTitle(_ title: String) -> Bool {
    title.hasPrefix("As a ") || title.trimmingCharacters(in: .whitespaces).isEmpty
}

private func typeShapeWarnings(_ draft: Draft) -> [String] {
    guard draft.ticketType == .bug else { return [] }
    var warnings: [String] = []
    if !hasBrokenStatement(draft.description) {
        warnings.append("Bug is missing a statement of what is broken")
    }
    if !hasNumberedSteps(draft.description) {
        warnings.append("Bug is missing steps to reproduce")
    }
    if !hasLabeledLine(draft.description, "Expected")
        || !hasLabeledLine(draft.description, "Actual")
    {
        warnings.append("Bug is missing Expected against Actual")
    }
    if !hasLabeledLine(draft.description, "Environment") {
        warnings.append("Bug is missing Environment")
    }
    return warnings
}

private func descriptionWarnings(_ description: String) -> [String] {
    var warnings: [String] = []
    if !description.contains("---") || !description.contains("- ") {
        warnings.append("a Definition of Done is missing")
    }
    let forbidden = ["Requirements", "Technical Notes", "Dependencies", "Out of Scope"]
    var hasMarkdownHeading = false
    for line in description.split(separator: "\n", omittingEmptySubsequences: false) {
        var heading = line.trimmingCharacters(in: .whitespaces)
        if heading.hasPrefix("#") {
            hasMarkdownHeading = true
        }
        while heading.hasPrefix("#") {
            heading = heading.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        if forbidden.contains(where: {
            heading.compare($0, options: .caseInsensitive) == .orderedSame
        }) {
            warnings.append("description contains a forbidden heading")
            break
        }
    }
    if hasMarkdownHeading || leavesMarkdownVocabulary(description) {
        warnings.append("description leaves the Markdown vocabulary")
    }
    if description.utf8.count > 1_048_576 {
        warnings.append("description exceeds the field cap")
    }
    return warnings
}

private func leavesMarkdownVocabulary(_ description: String) -> Bool {
    let rules = description.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { $0.trimmingCharacters(in: .whitespaces) == "---" }
        .count
    return rules > 1 || description.contains("```") || description.contains("![")
}

private func hasBrokenStatement(_ description: String) -> Bool {
    for line in description.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        if trimmed == "---" { continue }
        if trimmed.hasPrefix("#") { continue }
        if trimmed.range(of: "Definition of Done", options: .caseInsensitive) != nil {
            continue
        }
        if isLabeledLine(trimmed, "Expected") { continue }
        if isLabeledLine(trimmed, "Actual") { continue }
        if isLabeledLine(trimmed, "Environment") { continue }
        if trimmed.first?.isNumber == true { return false }
        return true
    }
    return false
}

private func hasNumberedSteps(_ description: String) -> Bool {
    description.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first.isNumber else { return false }
        return trimmed.contains(". ") || trimmed.contains(") ")
    }
}

private func hasLabeledLine(_ description: String, _ label: String) -> Bool {
    description.split(separator: "\n", omittingEmptySubsequences: false).contains {
        isLabeledLine($0.trimmingCharacters(in: .whitespaces), label)
    }
}

private func isLabeledLine(_ line: String, _ label: String) -> Bool {
    var text = line
    while text.hasPrefix("**") {
        text = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
    return text.lowercased().hasPrefix(label.lowercased())
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
    The agent never proposes a Batch. Fakthis holds the grouping.
    Vague Scope becomes a chat question in openQuestions, or stays blank plus the completeness marker.
    Functional, not technical, applies to Story and Bug.
    Story title: As a {Persona} I want {scope} so that {problem}. Bug title: the broken behaviour. Chore title: the action.
    Story: context paragraphs, bold nouns on first mention, related keys in prose. Bug: one-line statement of what is broken, numbered steps to reproduce, Expected against Actual, Environment. Chore: one paragraph of what and why.
    Markdown only: paragraphs, bold, bullet list, ordered list, links, one horizontal rule. No headings. No Requirements, Technical Notes, Dependencies, or Out of Scope headings.
    Definition of Done mirrors the description. It never introduces new Scope.
    """

private let draftJSONInstruction = """
    Reply with JSON only, no tools: ticketType (story, bug, or chore), title, shortLabel, description, openQuestions.
    """

private let generateInstruction = """
    \(draftJSONInstruction)
    Infer ticketType from the brain-dump. Default story if ambiguous. Do not ask ticket type as a question.
    """

private let rewriteGenerateInstruction = """
    \(draftJSONInstruction)
    Infer ticketType from the Material. Default story if ambiguous. Do not ask ticket type as a question.
    Reshape against the template from this Material. Never invent Scope.
    """

private let sendInstruction = """
    \(draftJSONInstruction)
    Revise the Draft from the chat answer.
    """

private func reshapeInstruction(_ ticketType: TicketType) -> String {
    """
    \(draftJSONInstruction)
    Reshape the Draft as a \(ticketType.rawValue). Keep Material and answers already given. Do not infer a different ticket type.
    """
}

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

private let matchStopWords: Set<String> = [
    "a", "an", "as", "i", "want", "so", "that", "to", "the", "of", "for", "and", "or",
    "in", "on", "with", "from",
]

private func matchTokens(_ text: String) -> Set<String> {
    Set(
        text.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { !$0.isEmpty && !matchStopWords.contains($0) }
    )
}

private func overlapCoefficient(_ intersection: Int, _ smaller: Int) -> Double {
    guard smaller > 0 else { return 0 }
    return Double(intersection) / Double(smaller)
}

private func isDuplicateScore(
    _ score: Double,
    intersection: Int,
    against: String,
    compared: String
) -> Bool {
    if against.compare(compared, options: .caseInsensitive) == .orderedSame { return true }
    return score >= 0.75 && intersection >= 2
}
