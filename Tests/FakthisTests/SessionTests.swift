import Foundation
import Testing
import Fakthis

@Test func generateProducesStoryDraftFromTypedBrainDumpWhenCatalogIsEmpty() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let state = try await harness.session.perform(.generate)

    let draft = try #require(state.draft)
    #expect(draft.ticketType == .story)
    #expect(draft.title == StoryReply.title)
    #expect(draft.title.hasPrefix("As a "))
    #expect(draft.shortLabel == StoryReply.shortLabel)
    #expect(!draft.shortLabel.lowercased().contains("as a"))
    #expect(draft.description.contains(StoryReply.firstPassDescription))
    #expect(draft.description.contains("---"))
    #expect(draft.description.contains(StoryReply.definitionOfDone))
    #expect(state.catalog.rows.isEmpty)

    let draftRequests = await harness.model.draftRequests
    #expect(draftRequests.count == 1)
    #expect(draftRequests[0].brainDump == StoryReply.brainDump)
    #expect(draftRequests[0].catalog.rows.isEmpty)
    #expect(draftRequests[0].projectTerms.isEmpty)

    let doneRequests = await harness.model.definitionOfDoneRequests
    #expect(doneRequests == [StoryReply.firstPassDescription])
}

@Test func generatedDraftLivesOnDiskAsSidecarMarkdownAndTranscript() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let state = try await harness.session.perform(.generate)
    let draft = try #require(state.draft)
    let folder = harness.draftFolder(id: draft.id)

    let sidecar = try JSONDecoder().decode(
        DiskSidecar.self,
        from: Data(contentsOf: folder.appending(component: "draft.json"))
    )
    #expect(sidecar.ticketType == .story)
    #expect(sidecar.title == StoryReply.title)
    #expect(sidecar.shortLabel == StoryReply.shortLabel)
    #expect(sidecar.openQuestions == [])
    #expect(sidecar.key == nil)

    let description = try String(
        contentsOf: folder.appending(component: "description.md"),
        encoding: .utf8
    )
    #expect(description == draft.description)

    let transcript = try String(
        contentsOf: folder.appending(component: "transcript.jsonl"),
        encoding: .utf8
    )
    #expect(transcript.contains(StoryReply.brainDump))
}

@Test func submitCreatesTicketOnJiraAndInsertsCatalogRowKeepingShortLabelAndType() async throws {
    let harness = Harness(ticketTypeMapping: [.story: "Task"])
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    let state = try await harness.session.perform(.submit)
    let draft = try #require(state.draft)

    #expect(draft.key == TicketKey("FAK-1"))

    let created = await harness.jira.created
    #expect(created.count == 1)
    let ticket = try #require(created.first)
    #expect(ticket.title == StoryReply.title)
    #expect(ticket.issueType == "Task")
    #expect(ticket.descriptionWiki.contains("*pick screen*"))
    #expect(ticket.descriptionWiki.contains("*bin*"))
    #expect(!ticket.descriptionWiki.contains("**"))
    #expect(ticket.descriptionWiki.contains("----"))
    #expect(
        ticket.descriptionWiki.contains("* \(StoryReply.definitionOfDone)")
    )

    #expect(state.catalog.rows.count == 1)
    #expect(state.catalog.rows[0].key == TicketKey("FAK-1"))
    #expect(state.catalog.rows[0].title == StoryReply.title)
    #expect(state.catalog.rows[0].jiraIssueType == "Task")
    #expect(state.catalog.rows[0].shortLabel == StoryReply.shortLabel)
    #expect(state.catalog.rows[0].ticketType == .story)
}

@Test func afterSubmitTheDraftFolderIsAnUploadQueueWithTheKeyNotAnEditor() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    let submitted = try await harness.session.perform(.submit)
    let draft = try #require(submitted.draft)
    let key = try #require(draft.key)
    let folder = harness.draftFolder(id: draft.id)

    #expect(FileManager.default.fileExists(atPath: folder.path))
    let sidecar = try JSONDecoder().decode(
        DiskSidecar.self,
        from: Data(contentsOf: folder.appending(component: "draft.json"))
    )
    #expect(sidecar.key == key.value)

    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: "As a thief I want to rewrite this Draft so that Generate is still an editor",
            shortLabel: "rewrite after submit",
            description: "This must not land on the Draft.",
            openQuestions: []
        )
    )
    let titleAfterSubmit = draft.title
    let descriptionAfterSubmit = draft.description
    _ = try await harness.session.perform(
        .typeBrainDump("a different dump that must not reshape the Ticket")
    )
    let afterGenerate = try await harness.session.perform(.generate)
    #expect(afterGenerate.draft?.title == titleAfterSubmit)
    #expect(afterGenerate.draft?.description == descriptionAfterSubmit)
    #expect(afterGenerate.draft?.key == key)

    _ = try await harness.session.perform(.submit)
    #expect(await harness.jira.created.count == 1)
}

@Test func unreachableJiraAtSubmitLeavesTheDraftAndRetrySucceeds() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    await harness.jira.setUnreachable(true)
    let failed = try await harness.session.perform(.submit)
    let draft = try #require(failed.draft)
    #expect(draft.key == nil)
    #expect(failed.catalog.rows.isEmpty)
    #expect(await harness.jira.created.isEmpty)
    let title = draft.title
    let description = draft.description

    await harness.jira.setUnreachable(false)
    let retried = try await harness.session.perform(.submit)
    #expect(retried.draft?.key == TicketKey("FAK-1"))
    #expect(retried.draft?.title == title)
    #expect(retried.draft?.description == description)
    #expect(retried.catalog.rows.count == 1)
    #expect(retried.catalog.rows[0].shortLabel == StoryReply.shortLabel)
    #expect(retried.catalog.rows[0].ticketType == .story)
}

private struct DiskSidecar: Decodable {
    var ticketType: TicketType
    var title: String
    var shortLabel: String
    var openQuestions: [String]
    var key: String?
}

private enum StoryReply {
    static let title =
        "As a warehouse picker I want to scan a bin so that I pick from the right location"
    static let shortLabel = "scan bin location"
    static let firstPassDescription =
        "On the **pick screen**, a picker scans the **bin** before taking items."
    static let definitionOfDone = "Pick screen requires a bin scan before items are taken"
    static let brainDump =
        "we need pickers to scan the bin before they pick so they don't grab from the wrong place"
}

private struct Harness {
    let model: ScriptedModel
    let jira: FakeJira
    let root: URL
    let session: Session

    init(ticketTypeMapping: [TicketType: String] = [.story: "Story"]) {
        let model = ScriptedModel(
            reply: GenerateReply(
                ticketType: .story,
                title: StoryReply.title,
                shortLabel: StoryReply.shortLabel,
                description: StoryReply.firstPassDescription,
                openQuestions: []
            ),
            definitionOfDone: [StoryReply.definitionOfDone]
        )
        let jira = FakeJira()
        let root = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        self.model = model
        self.jira = jira
        self.root = root
        self.session = Session(
            project: Project(key: "FAK", ticketTypeMapping: ticketTypeMapping, terms: []),
            applicationSupport: root,
            model: model,
            jira: jira
        )
    }

    func draftFolder(id: String) -> URL {
        root
            .appending(component: "projects")
            .appending(component: "FAK")
            .appending(component: "drafts")
            .appending(component: id)
    }
}
