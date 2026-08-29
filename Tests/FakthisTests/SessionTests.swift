import Foundation
import Testing
import Fakthis

@Test func pasteKeyFetchesLiveBodyAsMaterialAndBindsAnEmptyDraft() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_000),
                body: "The live description is messy.",
                comments: ["newest comment", "older comment"]
            )
        ],
        componentNames: []
    )

    let state = try await harness.session.perform(.pasteKey("FAK-231"))
    let draft = try #require(state.draft)
    #expect(draft.key == TicketKey("FAK-231"))
    #expect(draft.title.isEmpty)
    #expect(draft.description.isEmpty)
    #expect(draft.shortLabel.isEmpty)
    let rewrite = try #require(state.rewrite)
    #expect(rewrite.liveTitle == "Scan tote before pick")
    #expect(rewrite.liveDescription == "The live description is messy.")
    #expect(rewrite.comments == ["newest comment", "older comment"])
    #expect(rewrite.watchersNote.contains("FAK-231") == true)
    #expect(await harness.model.completeRequests.isEmpty)
    #expect(await harness.jira.created.isEmpty)
}

@Test func pasteKeyOnAMissingTicketIsAnErrorNotACreate() async throws {
    let harness = Harness()
    let state = try await harness.session.perform(.pasteKey("FAK-404"))
    #expect(state.draft == nil)
    #expect(state.rewrite == nil)
    #expect(state.rewriteError == "FAK-404 was not found")
    #expect(await harness.jira.created.isEmpty)
}

@Test func pasteKeyRejectsAnotherProjectsKey() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "ABC-1",
                title: "Other project ticket",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Must not become Material",
                comments: []
            )
        ],
        componentNames: []
    )
    let state = try await harness.session.perform(.pasteKey("ABC-1"))
    #expect(state.draft == nil)
    #expect(state.rewrite == nil)
    #expect(state.rewriteError == "ABC-1 is not in this Project")
    #expect(await harness.jira.fetchRewriteCalls.isEmpty)
}

@Test func pasteKeyRejectsAnEpicKey() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [
            SeededEpic(
                key: "FAK-100",
                name: "Warehouse picking",
                status: "In Progress",
                description: "Epic Scope"
            )
        ],
        issues: [
            SeededIssue(
                key: "FAK-100",
                title: "Warehouse picking",
                jiraIssueType: "Epic",
                labels: [],
                parentEpicKey: nil,
                status: "In Progress",
                created: Date(),
                body: "Epic Scope must not become a rewrite Draft",
                comments: []
            )
        ],
        componentNames: []
    )
    let state = try await harness.session.perform(.pasteKey("FAK-100"))
    #expect(state.draft == nil)
    #expect(state.rewrite == nil)
    #expect(state.rewriteError == "FAK-100 is an epic")
    #expect(await harness.jira.created.isEmpty)
}

@Test func unreachableJiraAtPasteKeyDoesNotStartARewrite() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "must not become Material",
                comments: []
            )
        ],
        componentNames: []
    )
    await harness.jira.setUnreachable(true)
    let state = try await harness.session.perform(.pasteKey("FAK-231"))
    #expect(state.draft == nil)
    #expect(state.rewrite == nil)
    #expect(state.rewriteError == nil)
}

@Test func emptyGenerateOnARewriteReshapesFromMaterialAndInventsNoScope() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Pickers scan a tote. Steps are missing.",
                comments: ["The expected result is still blank."]
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    #expect(draft.key == TicketKey("FAK-231"))
    #expect(draft.title == StoryReply.title)
    #expect(draft.shortLabel == StoryReply.shortLabel)
    #expect(draft.description.contains(StoryReply.definitionOfDone))

    let request = try #require(await harness.model.completeRequests.first)
    #expect(request.user.contains("Pickers scan a tote. Steps are missing."))
    #expect(request.user.contains("The expected result is still blank."))
    #expect(request.system.contains("Never invent Scope"))
    #expect(request.system.contains("Reshape"))
}

@Test func updateWritesTitleDescriptionAndCompletenessMarkerAndDoesNotChangeJiraIssueType()
    async throws
{
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Bug",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "The pick screen is wrong.",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    let ready = try await harness.session.perform(.generate)
    #expect(ready.rewrite?.watchersNote.contains("FAK-231") == true)
    let updated = try await harness.session.perform(.update)
    #expect(updated.draft?.key == TicketKey("FAK-231"))
    #expect(updated.rewrite == nil)

    #expect(await harness.jira.created.isEmpty)
    let write = try #require(await harness.jira.updated.first)
    #expect(write.key == TicketKey("FAK-231"))
    #expect(write.title == StoryReply.title)
    #expect(write.descriptionWiki.contains("----"))
    #expect(write.completenessMarker == .clear)

    let row = try #require(updated.catalog.rows.first { $0.key == TicketKey("FAK-231") })
    #expect(row.shortLabel == StoryReply.shortLabel)
    #expect(row.ticketType == .story)
}

@Test func leftoverCreateSubmitDoesNotWriteOverTheLiveTicket() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let created = try await harness.session.perform(.generate)
    let createId = try #require(created.draft?.id)
    #expect(created.draft?.key == nil)

    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-231"))
    #expect(await harness.jira.created.isEmpty)
    #expect(
        FileManager.default.fileExists(atPath: harness.draftFolder(id: createId).path)
    )
}

@Test func keepLiveTitlePutsTheFetchedTitleOnTheDraft() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.draft?.title == StoryReply.title)
    let kept = try await harness.session.perform(.keepLiveTitle)
    #expect(kept.draft?.title == "Scan tote before pick")
    #expect(kept.draft?.key == TicketKey("FAK-231"))
}

@Test func workOnDuplicateOfAJiraKeyOpensTheRewriteLoop() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: StoryReply.title,
                jiraIssueType: "Story",
                shortLabel: StoryReply.shortLabel,
                ticketType: .story
            )
        ],
        componentNames: []
    )
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: StoryReply.title,
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body as Material",
                comments: ["a comment"]
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.duplicateInterrupt?.key == TicketKey("FAK-231"))

    let rewritten = try await harness.session.perform(.workOnDuplicate)
    #expect(rewritten.duplicateInterrupt == nil)
    #expect(rewritten.draft?.key == TicketKey("FAK-231"))
    #expect(rewritten.draft?.title.isEmpty == true)
    #expect(rewritten.rewrite?.liveDescription == "Live body as Material")
    #expect(rewritten.rewrite?.comments == ["a comment"])
}

@Test func staleJiraAtUpdateWarnsAndRefetchKeepsTheDraft() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_000),
                body: "Original live body",
                comments: ["old comment"]
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    let generated = try await harness.session.perform(.generate)
    let title = try #require(generated.draft?.title)

    await harness.jira.replaceIssue(
        key: "FAK-231",
        title: "Scan tote before pick",
        body: "Someone edited this in Jira",
        comments: ["new comment"],
        updated: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let warned = try await harness.session.perform(.update)
    #expect(warned.rewrite?.stale == true)
    #expect(warned.draft?.title == title)
    #expect(await harness.jira.updated.isEmpty)

    let refreshed = try await harness.session.perform(.refetch)
    #expect(refreshed.rewrite?.stale == false)
    #expect(refreshed.rewrite?.liveDescription == "Someone edited this in Jira")
    #expect(refreshed.rewrite?.comments == ["new comment"])
    #expect(refreshed.draft?.title == title)

    let written = try await harness.session.perform(.update)
    #expect(await harness.jira.updated.count == 1)
    #expect(written.draft?.title == title)
}

@Test func staleJiraAtUpdateClobberWritesAnywayAndKeepsTheDraft() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_000),
                body: "Original live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    let generated = try await harness.session.perform(.generate)
    let title = try #require(generated.draft?.title)

    await harness.jira.replaceIssue(
        key: "FAK-231",
        title: "Scan tote before pick",
        body: "Someone edited this in Jira",
        comments: [],
        updated: Date(timeIntervalSince1970: 1_800_000_000)
    )
    _ = try await harness.session.perform(.update)
    #expect(await harness.jira.updated.isEmpty)

    let written = try await harness.session.perform(.clobber)
    #expect(written.draft?.title == title)
    #expect(await harness.jira.updated.count == 1)
}

@Test func updateDoesNotRequireGenerate() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    _ = try await harness.session.perform(.keepLiveTitle)
    let updated = try await harness.session.perform(.update)
    #expect(await harness.jira.created.isEmpty)
    let write = try #require(await harness.jira.updated.first)
    #expect(write.key == TicketKey("FAK-231"))
    #expect(write.title == "Scan tote before pick")
    #expect(updated.draft?.key == TicketKey("FAK-231"))
}

@Test func afterUpdateGenerateDoesNotKeepEditingTheTicket() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    _ = try await harness.session.perform(.generate)
    let updated = try await harness.session.perform(.update)
    #expect(updated.rewrite == nil)
    #expect(await harness.jira.updated.count == 1)

    _ = try await harness.session.perform(.generate)
    #expect(await harness.model.completeRequests.count == 2)
}

@Test func updateUpsertsTheCatalogRowWithShortLabelAndTicketType() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: ["warehouse"],
                parentEpicKey: TicketKey("FAK-100"),
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ],
        componentNames: []
    )
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: ["warehouse"],
                parentEpicKey: "FAK-100",
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_000),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    _ = try await harness.session.perform(.generate)
    let updated = try await harness.session.perform(.update)
    let row = try #require(updated.catalog.rows.first { $0.key == TicketKey("FAK-231") })
    #expect(row.shortLabel == StoryReply.shortLabel)
    #expect(row.ticketType == .story)
    #expect(row.labels == ["warehouse"])
    #expect(row.parentEpicKey == TicketKey("FAK-100"))
    #expect(row.status == "To Do")
    #expect(row.jiraIssueType == "Story")
}

@Test func unreachableJiraAtUpdateLeavesTheDraftAndRetrySucceeds() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    _ = try await harness.session.perform(.generate)
    await harness.jira.setUnreachable(true)
    let blocked = try await harness.session.perform(.update)
    #expect(blocked.draft?.key == TicketKey("FAK-231"))
    #expect(blocked.rewrite != nil)
    #expect(await harness.jira.updated.isEmpty)

    await harness.jira.setUnreachable(false)
    let retried = try await harness.session.perform(.update)
    #expect(await harness.jira.updated.count == 1)
    #expect(retried.draft?.key == TicketKey("FAK-231"))
}

@Test func pasteKeyDoesNotDownloadExistingAttachments() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    #expect(await harness.jira.uploadAttachmentCalls == 0)
    #expect(await harness.jira.attachmentPolicyCalls == 0)
    #expect(await harness.jira.created.isEmpty)
}

@Test func restartKeepsARewriteDraftBoundToTheKey() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "The live description is messy.",
                comments: ["newest comment"]
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    let generated = try await harness.session.perform(.generate)
    let title = try #require(generated.draft?.title)

    let restarted = harness.reopen()
    let restored = try await restarted.state()
    #expect(restored.draft?.key == TicketKey("FAK-231"))
    #expect(restored.draft?.title == title)
    #expect(restored.rewrite?.liveDescription == "The live description is messy.")
    #expect(restored.rewrite?.comments == ["newest comment"])

    let written = try await restarted.perform(.update)
    #expect(await harness.jira.updated.count == 1)
    #expect(written.draft?.title == title)
}

@Test func leftoverCreateFolderOnRestartStillDoesNotSubmitOverTheLiveTicket() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let created = try await harness.session.perform(.generate)
    let createId = try #require(created.draft?.id)
    _ = try await harness.session.perform(.pasteKey("FAK-231"))

    let restarted = harness.reopen()
    let submitted = try await restarted.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-231"))
    #expect(await harness.jira.created.isEmpty)
    #expect(
        FileManager.default.fileExists(atPath: harness.draftFolder(id: createId).path)
    )
}

@Test func sendOnARewriteRevisesTheDraftAndDoesNotCreate() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    _ = try await harness.session.perform(.generate)
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: "As a warehouse picker I want to scan a tote so that I pick from the right location",
            shortLabel: StoryReply.shortLabel,
            description: "Revised from the chat answer.",
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.typeBrainDump("call it a tote, not a bin"))
    let sent = try await harness.session.perform(.send)
    #expect(sent.draft?.key == TicketKey("FAK-231"))
    #expect(sent.draft?.description.contains("Revised from the chat answer") == true)
    #expect(await harness.jira.created.isEmpty)
    #expect(await harness.jira.updated.isEmpty)
}

@Test func spokenAskOnARewriteReplacesTheField() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: []
            )
        ],
        componentNames: []
    )
    await harness.transcriber.enqueueTake("call it a tote, not a bin")
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    _ = try await harness.session.perform(.typeBrainDump("typed ask"))
    _ = try await harness.session.perform(.startListening)
    let committed = try await harness.session.perform(.stopListening)
    #expect(committed.field == "call it a tote, not a bin")
    #expect(await harness.model.completeRequests.isEmpty)
}

@Test func refetchKeepsFilesThePMAttached() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_000),
                body: "Original live body",
                comments: ["old comment"]
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(
                filename: "client-email.txt",
                mimeType: "text/plain",
                data: Data("Please fix the tote scan.".utf8)
            )
        )
    )
    await harness.jira.replaceIssue(
        key: "FAK-231",
        title: "Scan tote before pick",
        body: "Someone edited this in Jira",
        comments: ["new comment"],
        updated: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let refreshed = try await harness.session.perform(.refetch)
    #expect(refreshed.rewrite?.liveDescription == "Someone edited this in Jira")
    #expect(refreshed.rewrite?.comments == ["new comment"])
    let generated = try await harness.session.perform(.generate)
    let request = try #require(await harness.model.completeRequests.first)
    #expect(request.user.contains("Please fix the tote scan."))
    #expect(request.user.contains("Someone edited this in Jira"))
    #expect(generated.draft?.key == TicketKey("FAK-231"))
}

@Test func rewriteGenerateHintsTicketTypeWhenJiraIssueTypeMapsOneToOne() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Bug",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "The pick screen is wrong.",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    _ = try await harness.session.perform(.generate)
    let request = try #require(await harness.model.completeRequests.first)
    #expect(request.system.contains("Jira issue type Bug maps 1:1 to bug"))
}

@Test func rewriteGenerateDoesNotHintTicketTypeWhenJiraIssueTypeMapsManyToOne() async throws {
    let harness = Harness(ticketTypeMapping: [
        .story: "Task",
        .bug: "Task",
        .chore: "Task",
    ])
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Task",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "The pick screen is wrong.",
                comments: []
            )
        ],
        componentNames: []
    )
    _ = try await harness.session.perform(.pasteKey("FAK-231"))
    _ = try await harness.session.perform(.generate)
    let request = try #require(await harness.model.completeRequests.first)
    #expect(request.system.contains("maps 1:1") == false)
}

@Test func rewriteCommentsCapAtFiftyAndSaySoWhenTruncated() async throws {
    let harness = Harness()
    let comments = (1...51).map { "comment \($0)" }
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "Live body",
                comments: comments
            )
        ],
        componentNames: []
    )
    let state = try await harness.session.perform(.pasteKey("FAK-231"))
    #expect(state.rewrite?.comments.count == 50)
    #expect(state.rewrite?.comments.first == "comment 1")
    #expect(state.rewrite?.commentsTruncated == true)
}

@Test func dumpToggleAppendsTheTakeAndGenerateIsASeparatePress() async throws {
    let harness = Harness()
    await harness.transcriber.enqueueTake(
        "we need pickers to scan the bin. no wait, actually the tote"
    )

    let listening = try await harness.session.perform(.startListening)
    #expect(listening.status == .listening)
    #expect(listening.field.isEmpty)
    #expect(await harness.model.completeRequests.isEmpty)

    let committed = try await harness.session.perform(.stopListening)
    #expect(committed.status == .yourTurn)
    #expect(committed.field == "we need pickers to scan the bin. no wait, actually the tote")
    #expect(await harness.model.completeRequests.isEmpty)

    let generated = try await harness.session.perform(.generate)
    #expect(generated.draft?.title == StoryReply.title)
    #expect(await harness.model.completeRequests.first?.user == committed.field)
}

@Test func aSecondDumpTakeAppendsSoTwoTakesAreOneBrainDump() async throws {
    let harness = Harness()
    await harness.transcriber.enqueueTake("we need pickers to scan the bin")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)

    await harness.transcriber.enqueueTake("no wait, actually the tote")
    let second = try await harness.session.perform(.startListening)
    #expect(second.status == .listening)
    let committed = try await harness.session.perform(.stopListening)
    #expect(committed.field == "we need pickers to scan the bin no wait, actually the tote")
    #expect(await harness.model.completeRequests.isEmpty)
}

@Test func chatTakeReplacesTheFieldAndSendIsASeparatePress() async throws {
    let harness = Harness()
    let generated = try await harness.generateStory(
        openQuestions: ["What should happen when the bin scan fails?"]
    )
    #expect(generated.field == StoryReply.brainDump)
    let requestsAfterGenerate = await harness.model.completeRequests.count

    await harness.transcriber.enqueueTake("show a blocking error and do not take items")
    _ = try await harness.session.perform(.startListening)
    let committed = try await harness.session.perform(.stopListening)
    #expect(committed.field == "show a blocking error and do not take items")
    #expect(await harness.model.completeRequests.count == requestsAfterGenerate)

    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: StoryReply.title,
            shortLabel: StoryReply.shortLabel,
            description: "When a **bin** scan fails, the **pick screen** shows a blocking error.",
            openQuestions: []
        )
    )
    let sent = try await harness.session.perform(.send)
    #expect(sent.draft?.openQuestions == [])
    #expect(sent.draft?.description.contains("blocking error") == true)
    let requests = await harness.model.completeRequests
    #expect(requests.count == requestsAfterGenerate + 2)
    #expect(requests[requestsAfterGenerate].user.contains("show a blocking error and do not take items"))
}

@Test func emptyProjectTermsMeanBiasingIsOffOnTheBatchPass() async throws {
    let harness = Harness()
    #expect(harness.project.terms.isEmpty)
    await harness.transcriber.enqueueTake("scan the bin")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    #expect(await harness.transcriber.transcribeTerms == [[]])
}

@Test func bothVoiceTiersPassProjectTermsOnTheBatchPass() async throws {
    let harness = Harness(terms: ["bin", "pick screen"])
    await harness.transcriber.enqueueTake("scan the bin")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    #expect(await harness.transcriber.transcribeTerms == [["bin", "pick screen"]])

    _ = try await harness.session.perform(.generate)
    await harness.transcriber.enqueueTake("show a blocking error")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    #expect(await harness.transcriber.transcribeTerms == [
        ["bin", "pick screen"],
        ["bin", "pick screen"],
    ])
}

@Test func typeOverAfterATakeIsWhatGenerateSends() async throws {
    let harness = Harness()
    await harness.transcriber.enqueueTake("scan the bin. no wait, actually the tote")
    _ = try await harness.session.perform(.startListening)
    let spoken = try await harness.session.perform(.stopListening)
    #expect(spoken.field.contains("no wait, actually"))

    let corrected = "pickers must scan the tote before they pick"
    _ = try await harness.session.perform(.typeBrainDump(corrected))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.field == corrected)
    #expect(await harness.model.completeRequests.first?.user == corrected)
}

@Test func generateDoesNotReceiveATakeThePMHasNotSeen() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    await harness.transcriber.enqueueTake("this take was never committed")
    let listening = try await harness.session.perform(.startListening)
    #expect(listening.status == .listening)
    #expect(listening.field == StoryReply.brainDump)

    let generated = try await harness.session.perform(.generate)
    #expect(generated.field == StoryReply.brainDump)
    #expect(await harness.model.completeRequests.first?.user == StoryReply.brainDump)
    #expect(await harness.transcriber.transcribeTerms.isEmpty)
}

@Test func stopListeningShowsTranscribingThenYourTurn() async throws {
    let harness = Harness()
    await harness.transcriber.enqueueTake("scan the bin")
    await harness.transcriber.setHoldTranscribe(true)
    _ = try await harness.session.perform(.startListening)

    async let stopped = harness.session.perform(.stopListening)
    try await waitUntil {
        try await harness.session.state().status == .transcribing
    }
    await harness.transcriber.setHoldTranscribe(false)
    let committed = try await stopped
    #expect(committed.status == .yourTurn)
    #expect(committed.field == "scan the bin")
}

@Test func generateShowsAgentThinkingThenYourTurn() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    await harness.model.setHoldComplete(true)

    async let generated = harness.session.perform(.generate)
    try await waitUntil {
        try await harness.session.state().status == .agentThinking
    }
    await harness.model.setHoldComplete(false)
    let done = try await generated
    #expect(done.status == .yourTurn)
    #expect(done.draft?.title == StoryReply.title)
}

@Test func aFailedTakeLeavesTheFieldAndReturnsToYourTurn() async throws {
    let harness = Harness()
    await harness.transcriber.enqueueTake("this must not land")
    await harness.transcriber.setFailTranscribe(true)
    _ = try await harness.session.perform(.startListening)
    let failed = try await harness.session.perform(.stopListening)
    #expect(failed.status == .yourTurn)
    #expect(failed.field.isEmpty)
    #expect(await harness.model.completeRequests.isEmpty)
}

@Test func firstLaunchShowsANECompileInProgressUntilItIsDone() async throws {
    let harness = Harness(seedProject: false, compileFinished: false)
    let compiling = try await harness.session.state()
    #expect(compiling.aneCompileInProgress)

    _ = try await harness.session.perform(firstLaunchCredentials)
    #expect(!FileManager.default.fileExists(atPath: harness.settingsURL.path))
    #expect(try await harness.session.state().settings == nil)

    await harness.transcriber.finishCompile()
    let ready = try await harness.session.state()
    #expect(!ready.aneCompileInProgress)
}

@Test func firstLaunchStoresSecretsOffDiskAndSettingsWithoutSecrets() async throws {
    let harness = Harness(seedProject: false)
    _ = try await harness.session.perform(firstLaunchCredentials)

    let state = try await harness.session.state()
    #expect(!state.aneCompileInProgress)
    let settings = try #require(state.settings)
    #expect(settings.site == "faktion.atlassian.net")
    #expect(settings.email == "pm@faktion.com")
    #expect(settings.provider == "openai")
    #expect(settings.modelId == "gpt-5.6-luna")

    #expect(try await harness.secrets.jiraToken() == "jira-secret")
    #expect(try await harness.secrets.modelKey() == "model-secret")

    let settingsJSON = try String(contentsOf: harness.settingsURL, encoding: .utf8)
    #expect(settingsJSON.contains("faktion.atlassian.net"))
    #expect(settingsJSON.contains("pm@faktion.com"))
    #expect(settingsJSON.contains("openai"))
    #expect(settingsJSON.contains("gpt-5.6-luna"))
    #expect(!settingsJSON.contains("jira-secret"))
    #expect(!settingsJSON.contains("model-secret"))

    let restarted = harness.reopen()
    let restored = try #require(try await restarted.state().settings)
    #expect(restored.site == "faktion.atlassian.net")
    #expect(restored.email == "pm@faktion.com")
    #expect(restored.provider == "openai")
    #expect(restored.modelId == "gpt-5.6-luna")
}

@Test func addingAProjectDiscoversIssueTypesAndShowsMappingForOverride() async throws {
    let harness = Harness(seedProject: false)
    await harness.jira.seedIssueTypes([
        JiraIssueType(name: "Epic", hierarchyLevel: 1, subtask: false),
        JiraIssueType(name: "Work", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Story", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Bug", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Sub-task", hierarchyLevel: -1, subtask: true),
    ])
    _ = try await harness.session.perform(firstLaunchCredentials)
    let state = try await harness.session.perform(.enterProjectKey("FAK"))

    let proposed = try #require(state.proposedProject)
    #expect(proposed.key == "FAK")
    #expect(proposed.mapping[TicketType.story] == "Story")
    #expect(proposed.mapping[TicketType.bug] == "Bug")
    #expect(proposed.mapping[TicketType.chore] == "Work")
    #expect(proposed.standardJiraIssueTypes == ["Work", "Story", "Bug"])
    #expect(state.project == nil)
}

@Test func confirmingAProjectStoresMappingEmptyTermsPullsCatalogAndWarnsAboutTextMaterial()
    async throws
{
    let harness = Harness(seedProject: false)
    await harness.jira.seedIssueTypes([
        JiraIssueType(name: "Epic", hierarchyLevel: 1, subtask: false),
        JiraIssueType(name: "Work", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Story", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Bug", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Sub-task", hierarchyLevel: -1, subtask: true),
    ])
    _ = try await harness.session.perform(firstLaunchCredentials)
    _ = try await harness.session.perform(.enterProjectKey("FAK"))
    let overridden: [TicketType: String] = [
        .story: "Story",
        .bug: "Bug",
        .chore: "Story",
    ]
    let state = try await harness.session.perform(.confirmProject(mapping: overridden))

    let project = try #require(state.project)
    #expect(project.key == "FAK")
    #expect(project.ticketTypeMapping == overridden)
    #expect(project.terms == [])
    #expect(state.proposedProject == nil)
    #expect(state.catalog.rows.isEmpty)
    #expect(state.catalog.epics.isEmpty)
    #expect(state.textMaterialWarning == "Text Material is sent to the model provider.")

    let onDisk = try JSONDecoder().decode(
        DiskProject.self,
        from: Data(contentsOf: harness.projectJSONURL)
    )
    #expect(onDisk.ticketTypeMapping == overridden)
    #expect(onDisk.terms == [])
    let projectJSON = try String(contentsOf: harness.projectJSONURL, encoding: .utf8)
    #expect(!projectJSON.contains("jira-secret"))
    #expect(!projectJSON.contains("model-secret"))

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.draft?.ticketType == .story)
    #expect(generated.catalog.rows.isEmpty)

    let restarted = harness.reopen()
    let restored = try #require(try await restarted.state().project)
    #expect(restored.key == "FAK")
    #expect(restored.ticketTypeMapping == overridden)
    #expect(restored.terms == [])
}

@Test func addingAProjectMapsAllTicketTypesOntoOneJiraIssueType() async throws {
    let harness = Harness(seedProject: false)
    await harness.jira.seedIssueTypes([
        JiraIssueType(name: "Epic", hierarchyLevel: 1, subtask: false),
        JiraIssueType(name: "Task", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Sub-task", hierarchyLevel: -1, subtask: true),
    ])
    _ = try await harness.session.perform(firstLaunchCredentials)
    let proposed = try await harness.session.perform(.enterProjectKey("FAK"))
    let mapping = try #require(proposed.proposedProject?.mapping)
    #expect(mapping[TicketType.story] == "Task")
    #expect(mapping[TicketType.bug] == "Task")
    #expect(mapping[TicketType.chore] == "Task")

    let confirmed = try await harness.session.perform(.confirmProject(mapping: mapping))
    #expect(confirmed.project?.ticketTypeMapping == mapping)
}

@Test func sendRevisesTheDraftFromAChatAnswerAndTypingAloneDoesNot() async throws {
    let harness = Harness()
    let question = "What should happen when the bin scan fails?"
    let generated = try await harness.generateStory(openQuestions: [question])
    #expect(generated.draft?.openQuestions == [question])
    let requestsAfterGenerate = await harness.model.completeRequests.count

    let answer = "show a blocking error and do not take items"
    _ = try await harness.session.perform(.typeBrainDump(answer))
    let typed = try await harness.session.state()
    #expect(typed.field == answer)
    #expect(typed.draft?.openQuestions == [question])
    #expect(typed.draft?.title == StoryReply.title)
    #expect(await harness.model.completeRequests.count == requestsAfterGenerate)

    let revisedTitle =
        "As a warehouse picker I want a bin scan error so that I do not pick from a failed scan"
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: revisedTitle,
            shortLabel: "bin scan failure",
            description: "When a **bin** scan fails, the **pick screen** shows a blocking error.",
            openQuestions: []
        )
    )
    let sent = try await harness.session.perform(.send)
    #expect(sent.draft?.title == revisedTitle)
    #expect(sent.draft?.openQuestions == [])
    #expect(sent.draft?.id == generated.draft?.id)
    #expect(sent.draft?.description.contains("blocking error") == true)
    #expect(sent.draft?.description.contains("---") == true)
    let requests = await harness.model.completeRequests
    #expect(requests.count == requestsAfterGenerate + 2)
    #expect(requests[requestsAfterGenerate].user.contains(answer))
    #expect(requests[requestsAfterGenerate].user.contains(StoryReply.title))
}

@Test func submitWithUnansweredQuestionsAppliesCompletenessMarkerAndSectionAboveTheHorizontalRule()
    async throws
{
    let harness = Harness()
    let question = "What should happen when the bin scan fails?"
    _ = try await harness.generateStory(openQuestions: [question])
    let state = try await harness.session.perform(.submit)
    #expect(state.draft?.key == TicketKey("FAK-1"))

    let ticket = try #require(await harness.jira.created.first)
    #expect(ticket.completenessMarker == .apply)
    #expect(ticket.descriptionWiki.contains("The reporter skipped these questions:"))
    #expect(ticket.descriptionWiki.contains("* \(question)"))
    let section = try #require(ticket.descriptionWiki.range(of: "The reporter skipped these questions:"))
    let horizontalRule = try #require(ticket.descriptionWiki.range(of: "----"))
    #expect(section.lowerBound < horizontalRule.lowerBound)
}

@Test func submitAfterQuestionsAreAnsweredOmitsCompletenessMarkerAndSection() async throws {
    let harness = Harness()
    let question = "What should happen when the bin scan fails?"
    _ = try await harness.generateStory(openQuestions: [question])
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: StoryReply.title,
            shortLabel: StoryReply.shortLabel,
            description: StoryReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(
        .typeBrainDump("show a blocking error and do not take items")
    )
    _ = try await harness.session.perform(.send)
    let state = try await harness.session.perform(.submit)
    #expect(state.draft?.key == TicketKey("FAK-1"))
    #expect(state.draft?.openQuestions == [])

    let ticket = try #require(await harness.jira.created.first)
    #expect(ticket.completenessMarker == .clear)
    #expect(!ticket.descriptionWiki.contains("The reporter skipped these questions:"))
    #expect(!ticket.descriptionWiki.contains(question))
    #expect(ticket.descriptionWiki.contains("----"))
}

@Test func relatedListCapsAtThreeDefaultsOffAndTickingIsContextForTheNextTurn() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [
            CatalogEpic(key: TicketKey("FAK-100"), name: "Warehouse picking", status: "In Progress")
        ],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: StoryReply.title,
                jiraIssueType: "Story",
                status: "Done",
                shortLabel: StoryReply.shortLabel,
                ticketType: .story
            ),
            CatalogRow(
                key: TicketKey("FAK-300"),
                title: "Scan tote before pick on the warehouse floor",
                jiraIssueType: "Story"
            ),
            CatalogRow(
                key: TicketKey("FAK-301"),
                title: "Picker labels on the pick screen",
                jiraIssueType: "Story"
            ),
            CatalogRow(
                key: TicketKey("FAK-302"),
                title: "Location audit for warehouse bins",
                jiraIssueType: "Story"
            ),
            CatalogRow(
                key: TicketKey("FAK-303"),
                title: "Dock assignment on the right side",
                jiraIssueType: "Story"
            ),
            CatalogRow(
                key: TicketKey("FAK-400"),
                title: "Rewrite the invoice PDF renderer",
                jiraIssueType: "Story",
                labels: ["picking"],
                parentEpicKey: TicketKey("FAK-100")
            ),
        ],
        componentNames: []
    )

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.duplicateInterrupt == nil)
    #expect(generated.related.count == 3)
    #expect(generated.related.allSatisfy { !$0.ticked })
    #expect(generated.related.map(\.key).contains(TicketKey("FAK-231")))
    #expect(!generated.related.map(\.key).contains(TicketKey("FAK-400")))

    let ticked = try await harness.session.perform(.tickRelated(TicketKey("FAK-231")))
    #expect(ticked.related.first { $0.key == TicketKey("FAK-231") }?.ticked == true)
    #expect(ticked.draft?.description.contains("FAK-231") == false)

    let regenerated = try await harness.session.perform(.generate)
    #expect(regenerated.related.first { $0.key == TicketKey("FAK-231") }?.ticked == true)
    #expect(regenerated.draft?.description.contains("FAK-231") == false)
    let generateRequest = try #require(await harness.model.completeRequests.last { request in
        request.user.contains(StoryReply.brainDump)
    })
    #expect(generateRequest.user.contains("FAK-231"))
    #expect(generateRequest.user.contains("Related:"))

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.created.count == 1)
    #expect(await harness.jira.blocksLinks.isEmpty)
}

@Test func doneIsNeverADuplicateInterrupt() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: StoryReply.title,
                jiraIssueType: "Story",
                status: "Done",
                shortLabel: StoryReply.shortLabel,
                ticketType: .story
            )
        ],
        componentNames: []
    )

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.duplicateInterrupt == nil)
}

@Test func duplicateSkipsTypeFilterOnManyToOneJiraPulledRowsAndAppliesItWhenMappingIsOneToOne()
    async throws
{
    let oneToOne = Harness()
    try oneToOne.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: StoryReply.title,
                jiraIssueType: "Bug"
            )
        ],
        componentNames: []
    )
    _ = try await oneToOne.session.perform(.typeBrainDump(StoryReply.brainDump))
    let filtered = try await oneToOne.session.perform(.generate)
    #expect(filtered.duplicateInterrupt == nil)

    let manyToOne = Harness(ticketTypeMapping: [
        .story: "Task",
        .bug: "Task",
        .chore: "Task",
    ])
    try manyToOne.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: StoryReply.title,
                jiraIssueType: "Task"
            )
        ],
        componentNames: []
    )
    _ = try await manyToOne.session.perform(.typeBrainDump(StoryReply.brainDump))
    let unfiltered = try await manyToOne.session.perform(.generate)
    #expect(unfiltered.duplicateInterrupt?.key == TicketKey("FAK-231"))
}

@Test func duplicateRequiresTheSameTicketTypeWhenTheCatalogRowKnowsIt() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: StoryReply.title,
                jiraIssueType: "Bug",
                shortLabel: StoryReply.shortLabel,
                ticketType: .bug
            )
        ],
        componentNames: []
    )

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.draft?.ticketType == .story)
    #expect(generated.duplicateInterrupt == nil)
}

@Test func changingTypeOrShortLabelRerunsDuplicateMatching() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: BugReply.title,
                jiraIssueType: "Bug",
                shortLabel: BugReply.shortLabel,
                ticketType: .bug
            )
        ],
        componentNames: []
    )

    let generated = try await harness.generateStory()
    #expect(generated.draft?.ticketType == .story)
    #expect(generated.duplicateInterrupt == nil)

    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .bug,
            title: BugReply.title,
            shortLabel: BugReply.shortLabel,
            description: BugReply.firstPassDescription,
            openQuestions: []
        )
    )
    let reshaped = try await harness.session.perform(.changeTicketType(.bug))
    #expect(reshaped.draft?.ticketType == .bug)
    #expect(reshaped.duplicateInterrupt?.key == TicketKey("FAK-231"))
}

@Test func submitRerunsDuplicateMatchingAndStillCreatesTheTicket() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: StoryReply.title,
                jiraIssueType: "Story",
                shortLabel: StoryReply.shortLabel,
                ticketType: .story
            )
        ],
        componentNames: []
    )

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.duplicateInterrupt?.key == TicketKey("FAK-231"))

    _ = try await harness.session.perform(.dismissDuplicate)
    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(submitted.duplicateInterrupt?.key == TicketKey("FAK-231"))
    #expect(await harness.jira.created.count == 1)
}

@Test func localDraftDuplicateIsNamedByShortLabelAndWorkOnThatFocusesIt() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let currentId = try #require(generated.draft?.id)
    #expect(generated.duplicateInterrupt == nil)

    let otherId = "other-draft"
    try harness.writeDraft(
        id: otherId,
        ticketType: .story,
        title: "As a picker I want to scan a bin so that I pick from the right location",
        shortLabel: StoryReply.shortLabel,
        description: "A sibling Draft about scanning a bin."
    )

    let rematched = try await harness.session.perform(.generate)
    let hit = try #require(rematched.duplicateInterrupt)
    #expect(hit.key == nil)
    #expect(hit.draftId == otherId)
    #expect(hit.shortLabel == StoryReply.shortLabel)
    #expect(rematched.draft?.id == currentId)

    let focused = try await harness.session.perform(.workOnDuplicate)
    #expect(focused.duplicateInterrupt == nil)
    #expect(focused.draft?.id == otherId)
    #expect(focused.draft?.description == "A sibling Draft about scanning a bin.")
    #expect(focused.draft?.shortLabel == StoryReply.shortLabel)
}

@Test func afterGenerateAJiraPulledRowMatchesOnTitleTokensWhenItHasNoShortLabel() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: StoryReply.title,
                jiraIssueType: "Story"
            )
        ],
        componentNames: []
    )

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let hit = try #require(generated.duplicateInterrupt)
    #expect(hit.key == TicketKey("FAK-231"))
    #expect(hit.shortLabel == nil)
    #expect(hit.title == StoryReply.title)
}

@Test func afterGenerateAMatchingCatalogShortLabelIsADismissibleDuplicateAndDoesNotBlockSubmit()
    async throws
{
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: StoryReply.title,
                jiraIssueType: "Story",
                shortLabel: StoryReply.shortLabel,
                ticketType: .story
            )
        ],
        componentNames: []
    )

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let hit = try #require(generated.duplicateInterrupt)
    #expect(hit.key == TicketKey("FAK-231"))
    #expect(hit.shortLabel == StoryReply.shortLabel)
    #expect(generated.related.isEmpty)

    let continued = try await harness.session.perform(.dismissDuplicate)
    #expect(continued.duplicateInterrupt == nil)
    #expect(continued.draft?.title == StoryReply.title)

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.created.count == 1)
    #expect(await harness.jira.blocksLinks.isEmpty)
}

@Test func structuralWarningsDoNotBlockSubmitOrApplyTheCompletenessLabel() async throws {
    let harness = Harness()
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: "Scan the bin before picking",
            shortLabel: "scan bin",
            description: StoryReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(!generated.structuralWarnings.isEmpty)

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(submitted.structuralWarnings.isEmpty == false)
    let ticket = try #require(await harness.jira.created.first)
    #expect(ticket.completenessMarker == CompletenessMarker.clear)
}

@Test func generateInfersBugFromTheBrainDumpAndSubmitsTheMappedJiraIssueType() async throws {
    let harness = Harness()
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .bug,
            title: BugReply.title,
            shortLabel: BugReply.shortLabel,
            description: BugReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(BugReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    #expect(draft.ticketType == .bug)
    #expect(draft.title == BugReply.title)
    #expect(draft.shortLabel == BugReply.shortLabel)
    #expect(draft.description.contains("The pick screen does not show an error"))
    #expect(draft.description.contains("1. Open a pick"))
    #expect(draft.description.contains("Expected"))
    #expect(draft.description.contains("Actual"))
    #expect(draft.description.contains("Environment"))
    #expect(draft.description.contains("---"))
    #expect(draft.description.contains("Definition of Done"))
    #expect(draft.openQuestions.isEmpty)

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    let ticket = try #require(await harness.jira.created.first)
    #expect(ticket.jiraIssueType == "Bug")
    #expect(ticket.title == BugReply.title)
    #expect(ticket.completenessMarker == CompletenessMarker.clear)
}

@Test func generateInfersChoreFromTheBrainDumpAndSubmitsTheMappedJiraIssueType() async throws {
    let harness = Harness()
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: ChoreReply.shortLabel,
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(ChoreReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    #expect(draft.ticketType == .chore)
    #expect(draft.title == ChoreReply.title)
    #expect(draft.shortLabel == ChoreReply.shortLabel)
    #expect(draft.description.contains("Bump the scanner SDK"))
    #expect(draft.description.contains("---"))
    #expect(draft.description.contains("Definition of Done"))
    #expect(draft.openQuestions.isEmpty)

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    let ticket = try #require(await harness.jira.created.first)
    #expect(ticket.jiraIssueType == "Chore")
    #expect(ticket.title == ChoreReply.title)
}

@Test func generateDefaultsToStoryWhenTheInferredTypeIsAmbiguous() async throws {
    let harness = Harness()
    await harness.model.replaceRawReply("""
        {"ticketType":"task","title":"\(StoryReply.title)","shortLabel":"\(StoryReply.shortLabel)","description":"\(StoryReply.firstPassDescription)","openQuestions":[]}
        """)
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    #expect(draft.ticketType == .story)
    #expect(draft.title == StoryReply.title)
}

@Test func changingTicketTypeMidChatReshapesTheDraftAndKeepsMaterialAndAnswers() async throws {
    let harness = Harness()
    let email = "From: client@acme.com\nThe pick screen shows nothing when the bin scan fails."
    let screenshot = Material(
        filename: "scan-fail.png",
        mimeType: "image/png",
        data: Data("png-bytes".utf8)
    )
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(
                filename: "client-email.txt",
                mimeType: "text/plain",
                data: Data(email.utf8)
            )
        )
    )
    _ = try await harness.session.perform(.attachMaterial(screenshot))
    let generated = try await harness.generateStory(
        openQuestions: ["What should happen when the bin scan fails?"]
    )
    let draftId = try #require(generated.draft?.id)

    let answer = "show a blocking error and do not take items"
    _ = try await harness.session.perform(.typeBrainDump(answer))
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: StoryReply.title,
            shortLabel: "bin scan failure",
            description: "When a **bin** scan fails, the **pick screen** shows a blocking error.",
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.send)

    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: BugReply.title,
            shortLabel: BugReply.shortLabel,
            description: BugReply.firstPassDescription,
            openQuestions: []
        )
    )
    let reshaped = try await harness.session.perform(.changeTicketType(.bug))
    let draft = try #require(reshaped.draft)
    #expect(draft.id == draftId)
    #expect(draft.ticketType == .bug)
    #expect(draft.title == BugReply.title)
    #expect(draft.description.contains("1. Open a pick"))
    #expect(draft.description.contains("Expected"))
    #expect(draft.description.contains("Actual"))
    #expect(draft.description.contains("Environment"))

    let requests = await harness.model.completeRequests
    let reshapeRequest = requests[requests.count - 2]
    #expect(reshapeRequest.user.contains(answer) || reshapeRequest.user.contains("blocking error"))
    #expect(reshapeRequest.user.contains("client-email.txt"))
    #expect(reshapeRequest.user.contains(email))
    #expect(reshapeRequest.screenshots == [screenshot])

    let folder = harness.draftFolder(id: draftId).appending(component: "material")
    #expect(
        FileManager.default.fileExists(
            atPath: folder.appending(component: "client-email.txt").path
        )
    )
    #expect(
        FileManager.default.fileExists(
            atPath: folder.appending(component: "scan-fail.png").path
        )
    )
}

@Test func structuralCheckWarnsOnBugShapeWithoutBlockingSubmitOrApplyingTheCompletenessLabel()
    async throws
{
    let harness = Harness()
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .bug,
            title: "As a picker I want a scan error so that I stop",
            shortLabel: "scan error",
            description: "Something broke.",
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(BugReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.structuralWarnings.contains("title does not match the Bug convention"))
    #expect(generated.structuralWarnings.contains("Bug is missing steps to reproduce"))
    #expect(generated.structuralWarnings.contains("Bug is missing Expected against Actual"))
    #expect(generated.structuralWarnings.contains("Bug is missing Environment"))

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(submitted.structuralWarnings.isEmpty == false)
    let ticket = try #require(await harness.jira.created.first)
    #expect(ticket.completenessMarker == CompletenessMarker.clear)
}

@Test func structuralCheckWarnsWhenOutputLeavesTheMarkdownVocabulary() async throws {
    let harness = Harness()
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: StoryReply.title,
            shortLabel: StoryReply.shortLabel,
            description: """
                \(StoryReply.firstPassDescription)

                # Overview
                """,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.structuralWarnings.contains("description leaves the Markdown vocabulary"))
}

@Test func aWellFormedBugHasNoStructuralWarnings() async throws {
    let harness = Harness()
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .bug,
            title: BugReply.title,
            shortLabel: BugReply.shortLabel,
            description: BugReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(BugReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.structuralWarnings.isEmpty)
}

@Test func structuralCheckWarnsWhenAChoreTitleUsesTheStoryConvention() async throws {
    let harness = Harness()
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: "As a picker I want the SDK upgraded so that labels scan",
            shortLabel: ChoreReply.shortLabel,
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(ChoreReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.structuralWarnings.contains("title does not match the Chore convention"))
}

@Test func aWellFormedChoreHasNoStructuralWarnings() async throws {
    let harness = Harness()
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: ChoreReply.shortLabel,
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(ChoreReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.structuralWarnings.isEmpty)
}

@Test func submitDoesNotQueryAttachmentPolicyWhenTheDraftHasNoMedia() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    let state = try await harness.session.perform(.submit)
    #expect(state.draft?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.attachmentPolicyCalls == 0)
    #expect(await harness.jira.uploadAttachmentCalls == 0)
}

@Test func textMaterialGoesToGenerateAndIsNeverAJiraAttachment() async throws {
    let harness = Harness()
    let email = "From: client@acme.com\nWe need pickers to scan the bin before they pick."
    let attached = try await harness.session.perform(
        .attachMaterial(
            Material(
                filename: "client-email.txt",
                mimeType: "text/plain",
                data: Data(email.utf8)
            )
        )
    )
    #expect(attached.textMaterialWarning == "Text Material is sent to the model provider.")
    #expect(await harness.jira.attachmentPolicyCalls == 0)

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    let onDisk = try String(
        contentsOf: harness.draftFolder(id: draft.id)
            .appending(component: "material")
            .appending(component: "client-email.txt"),
        encoding: .utf8
    )
    #expect(onDisk == email)

    let requests = await harness.model.completeRequests
    #expect(requests[0].user.contains(StoryReply.brainDump))
    #expect(requests[0].user.contains(email))
    #expect(requests[0].user.contains("client-email.txt"))

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.uploadAttachmentCalls == 0)
    #expect(await harness.jira.created.count == 1)
    #expect(
        !FileManager.default.fileExists(
            atPath: harness.draftFolder(id: try #require(submitted.draft?.id)).path
        )
    )
}

@Test func screenshotsGoToGenerateAndUploadAfterTheTicketExists() async throws {
    let harness = Harness()
    let png = Data("fake-png-bytes".utf8)
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "pick.png", mimeType: "image/png", data: png)
        )
    )
    #expect(await harness.jira.attachmentPolicyCalls == 1)

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    let onDisk = try Data(
        contentsOf: harness.draftFolder(id: draft.id)
            .appending(component: "material")
            .appending(component: "pick.png")
    )
    #expect(onDisk == png)

    let generateRequest = try #require(await harness.model.completeRequests.first)
    #expect(generateRequest.user == StoryReply.brainDump)
    #expect(generateRequest.screenshots.map(\.filename) == ["pick.png"])
    #expect(generateRequest.screenshots.first?.mimeType == "image/png")
    #expect(generateRequest.screenshots.first?.data == png)

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    let uploads = await harness.jira.uploaded
    #expect(uploads.count == 1)
    #expect(uploads[0].key == TicketKey("FAK-1"))
    #expect(uploads[0].filename == "pick.png")
    #expect(uploads[0].mimeType == "image/png")
    #expect(uploads[0].data == png)
    #expect(
        !FileManager.default.fileExists(
            atPath: harness.draftFolder(id: try #require(submitted.draft?.id)).path
        )
    )
}

@Test func videoDoesNotGoToTheModelAndUploadsAfterTheTicketExists() async throws {
    let harness = Harness()
    let video = Data("fake-mp4-bytes".utf8)
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "repro.mp4", mimeType: "video/mp4", data: video)
        )
    )
    #expect(await harness.jira.attachmentPolicyCalls == 1)

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    let onDisk = try Data(
        contentsOf: harness.draftFolder(id: draft.id)
            .appending(component: "material")
            .appending(component: "repro.mp4")
    )
    #expect(onDisk == video)

    let generateRequest = try #require(await harness.model.completeRequests.first)
    #expect(generateRequest.user == StoryReply.brainDump)
    #expect(generateRequest.screenshots.isEmpty)
    #expect(!generateRequest.user.contains("fake-mp4-bytes"))

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    let uploads = await harness.jira.uploaded
    #expect(uploads.count == 1)
    #expect(uploads[0].key == TicketKey("FAK-1"))
    #expect(uploads[0].filename == "repro.mp4")
    #expect(uploads[0].mimeType == "video/mp4")
    #expect(uploads[0].data == video)
}

@Test func oversizeMediaWarnsKeepsTheFileAndDoesNotBlockGenerateOrSubmit() async throws {
    let harness = Harness()
    await harness.jira.setAttachmentPolicy(AttachmentPolicy(enabled: true, uploadLimit: 10))
    let png = Data("this-screenshot-is-oversize".utf8)
    let attached = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "pick.png", mimeType: "image/png", data: png)
        )
    )
    #expect(attached.materialWarnings == ["pick.png is oversize"])
    #expect(await harness.jira.attachmentPolicyCalls == 1)

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    #expect(draft.title == StoryReply.title)
    let onDisk = try Data(
        contentsOf: harness.draftFolder(id: draft.id)
            .appending(component: "material")
            .appending(component: "pick.png")
    )
    #expect(onDisk == png)
    #expect(await harness.model.completeRequests.first?.screenshots.first?.data == png)

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.uploaded.isEmpty)
}

@Test func restartStillSkipsOversizeMediaOnSubmit() async throws {
    let harness = Harness()
    await harness.jira.setAttachmentPolicy(AttachmentPolicy(enabled: true, uploadLimit: 10))
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(
                filename: "pick.png",
                mimeType: "image/png",
                data: Data("this-screenshot-is-oversize".utf8)
            )
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)

    let restarted = harness.reopen()
    let submitted = try await restarted.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.uploaded.isEmpty)
}

@Test func disabledAttachmentsWarnKeepTheFileAndDoNotBlockGenerateOrSubmit() async throws {
    let harness = Harness()
    await harness.jira.setAttachmentPolicy(AttachmentPolicy(enabled: false, uploadLimit: 10_485_760))
    let png = Data("png-bytes".utf8)
    let attached = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "pick.png", mimeType: "image/png", data: png)
        )
    )
    #expect(attached.materialWarnings == ["attachments are disabled"])

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    #expect(draft.title == StoryReply.title)
    #expect(
        FileManager.default.fileExists(
            atPath: harness.draftFolder(id: draft.id)
                .appending(component: "material")
                .appending(component: "pick.png")
                .path
        )
    )
    #expect(await harness.model.completeRequests.first?.screenshots.map(\.filename) == ["pick.png"])

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.uploaded.isEmpty)
}

@Test func unsupportedMaterialWarnsKeepsTheFileAndDoesNotBlockGenerateOrSubmit() async throws {
    let harness = Harness()
    let pdf = Data("%PDF-fake".utf8)
    let attached = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "notes.pdf", mimeType: "application/pdf", data: pdf)
        )
    )
    #expect(attached.materialWarnings == ["notes.pdf is unsupported"])
    #expect(await harness.jira.attachmentPolicyCalls == 0)

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    #expect(draft.title == StoryReply.title)
    let onDisk = try Data(
        contentsOf: harness.draftFolder(id: draft.id)
            .appending(component: "material")
            .appending(component: "notes.pdf")
    )
    #expect(onDisk == pdf)
    #expect(await harness.model.completeRequests.first?.screenshots.isEmpty == true)
    #expect(await harness.model.completeRequests.first?.user == StoryReply.brainDump)

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.uploaded.isEmpty)
}

@Test func failedMediaUploadLeavesTheQueueAndRetryDeletesTheFolder() async throws {
    let harness = Harness()
    let png = Data("png-bytes".utf8)
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "pick.png", mimeType: "image/png", data: png)
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draftId = try #require(generated.draft?.id)
    let folder = harness.draftFolder(id: draftId)

    await harness.jira.setFailUploads(true)
    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.created.count == 1)
    #expect(await harness.jira.uploaded.isEmpty)
    #expect(submitted.failedUploads == ["pick.png"])
    #expect(FileManager.default.fileExists(atPath: folder.path))
    let sidecar = try JSONDecoder().decode(
        DiskSidecar.self,
        from: Data(contentsOf: folder.appending(component: "draft.json"))
    )
    #expect(sidecar.key == "FAK-1")

    await harness.jira.setFailUploads(false)
    let retried = try await harness.session.perform(.retryUploads)
    #expect(retried.failedUploads.isEmpty)
    let uploads = await harness.jira.uploaded
    #expect(uploads.count == 1)
    #expect(uploads[0].filename == "pick.png")
    #expect(uploads[0].data == png)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
}

@Test func skippingFailedUploadsDeletesTheDraftFolder() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "repro.mp4", mimeType: "video/mp4", data: Data("vid".utf8))
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let folder = harness.draftFolder(id: try #require(generated.draft?.id))

    await harness.jira.setFailUploads(true)
    _ = try await harness.session.perform(.submit)
    let skipped = try await harness.session.perform(.skipFailedUploads)
    #expect(skipped.failedUploads.isEmpty)
    #expect(await harness.jira.uploaded.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
}

@Test func restartKeepsMaterialAndUploadsItOnSubmit() async throws {
    let harness = Harness()
    let png = Data("png-bytes".utf8)
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(
                filename: "client-email.txt",
                mimeType: "text/plain",
                data: Data("client says the pick screen is wrong".utf8)
            )
        )
    )
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "pick.png", mimeType: "image/png", data: png)
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)

    let restarted = harness.reopen()
    let submitted = try await restarted.perform(.submit)
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    let uploads = await harness.jira.uploaded
    #expect(uploads.map(\.filename) == ["pick.png"])
    #expect(uploads.first?.data == png)
}

@Test func restartRetriesAFailedUploadQueueThenDeletesTheFolder() async throws {
    let harness = Harness()
    let png = Data("png-bytes".utf8)
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "pick.png", mimeType: "image/png", data: png)
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let folder = harness.draftFolder(id: try #require(generated.draft?.id))

    await harness.jira.setFailUploads(true)
    _ = try await harness.session.perform(.submit)

    let restarted = harness.reopen()
    let queued = try await restarted.state()
    #expect(queued.draft?.key == TicketKey("FAK-1"))
    #expect(queued.failedUploads == ["pick.png"])
    #expect(queued.draft?.title == StoryReply.title)

    await harness.jira.setFailUploads(false)
    let retried = try await restarted.perform(.retryUploads)
    #expect(retried.failedUploads.isEmpty)
    #expect(await harness.jira.uploaded.map(\.filename) == ["pick.png"])
    #expect(!FileManager.default.fileExists(atPath: folder.path))
}

@Test func restartBeforeGenerateKeepsTextMaterialForGenerate() async throws {
    let harness = Harness()
    let email = "From: client@acme.com\nScan the bin before pick."
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "client-email.txt", mimeType: "text/plain", data: Data(email.utf8))
        )
    )

    let restarted = harness.reopen()
    _ = try await restarted.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await restarted.perform(.generate)
    let user = try #require(await harness.model.completeRequests.first?.user)
    #expect(user.contains(email))
    #expect(user.contains("client-email.txt"))
}

@Test func afterSubmitLocalInsertKeepsShortLabelAndTypeWhenThePullReturnsTheRowWithoutThem()
    async throws
{
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date().addingTimeInterval(-3601),
        epics: [],
        rows: [],
        componentNames: []
    )
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-1",
                title: StoryReply.title,
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_200),
                body: "Jira has the issue and no Fakthis fields",
                comments: []
            )
        ],
        componentNames: []
    )
    await harness.jira.setHoldPulls(true)

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    _ = try await harness.session.perform(.submit)

    await harness.jira.setHoldPulls(false)
    try await waitUntil {
        try await harness.session.state().catalog.rows.contains {
            $0.key == TicketKey("FAK-1") && $0.status == "To Do"
        }
    }
    let inserted = try #require(
        try await harness.session.state().catalog.rows.first { $0.key == TicketKey("FAK-1") }
    )
    #expect(inserted.shortLabel == StoryReply.shortLabel)
    #expect(inserted.ticketType == .story)
    #expect(inserted.status == "To Do")
}

@Test func afterSubmitLocalInsertKeepsShortLabelAndTypeWhenAPullOmitsTheNewRow() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date().addingTimeInterval(-3601),
        epics: [
            CatalogEpic(key: TicketKey("FAK-100"), name: "Warehouse picking", status: "In Progress")
        ],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: ["picking"],
                parentEpicKey: TicketKey("FAK-100"),
                status: "To Do"
            )
        ],
        componentNames: ["Pick App"]
    )
    await harness.jira.seed(
        epics: [
            SeededEpic(
                key: "FAK-100",
                name: "Warehouse picking",
                status: "In Progress",
                description: "Epic Scope"
            )
        ],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick — refreshed",
                jiraIssueType: "Story",
                labels: ["picking"],
                parentEpicKey: "FAK-100",
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_000),
                body: "FAK-231 body is Scope",
                comments: []
            )
        ],
        componentNames: ["Pick App"]
    )
    await harness.jira.setHoldPulls(true)

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.catalog.rows.contains { row in
        row.key == TicketKey("FAK-1") && row.shortLabel == StoryReply.shortLabel
            && row.ticketType == .story
    })

    await harness.jira.setHoldPulls(false)
    try await waitUntil {
        try await harness.session.state().catalog.rows.contains {
            $0.key == TicketKey("FAK-231") && $0.title == "Scan tote before pick — refreshed"
        }
    }
    let catalog = try await harness.session.state().catalog
    let inserted = try #require(catalog.rows.first { $0.key == TicketKey("FAK-1") })
    #expect(inserted.shortLabel == StoryReply.shortLabel)
    #expect(inserted.ticketType == .story)
    #expect(inserted.title == StoryReply.title)
    #expect(catalog.rows.contains { $0.key == TicketKey("FAK-231") })
}

@Test func laterOpenDoesNotRefreshACatalogPulledWithinTheHour() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date().addingTimeInterval(-60),
        epics: [
            CatalogEpic(key: TicketKey("FAK-100"), name: "Warehouse picking", status: "In Progress")
        ],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: "Scan tote before pick",
                jiraIssueType: "Story"
            )
        ],
        componentNames: ["Pick App"]
    )
    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-400",
                title: "A different recent title",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(),
                body: "must not be pulled yet",
                comments: []
            )
        ],
        componentNames: []
    )

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let state = try await harness.session.perform(.generate)

    #expect(state.catalog.rows.first?.title == "Scan tote before pick")
    #expect(await harness.jira.catalogPulls.isEmpty)
}

@Test func laterOpenDoesNotBlockGenerateOnAStaleCatalogRefresh() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date().addingTimeInterval(-3601),
        epics: [
            CatalogEpic(key: TicketKey("FAK-100"), name: "Warehouse picking", status: "In Progress")
        ],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: ["picking"],
                parentEpicKey: TicketKey("FAK-100"),
                status: "To Do"
            )
        ],
        componentNames: ["Pick App"]
    )
    await harness.jira.seed(
        epics: [
            SeededEpic(
                key: "FAK-100",
                name: "Warehouse picking",
                status: "In Progress",
                description: "Epic Scope"
            )
        ],
        issues: [
            SeededIssue(
                key: "FAK-400",
                title: "A different recent title",
                jiraIssueType: "Story",
                labels: ["picking"],
                parentEpicKey: "FAK-100",
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_100),
                body: "Body of FAK-400 must not reach Generate",
                comments: []
            )
        ],
        componentNames: ["Pick App"]
    )
    await harness.jira.setHoldPulls(true)

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)

    #expect(generated.catalog.rows.first?.title == "Scan tote before pick")
    #expect(generated.catalog.rows.first?.key == TicketKey("FAK-231"))
    let sent = try #require(await harness.model.completeRequests.first?.system)
    #expect(sent.contains("Scan tote before pick"))
    try await waitUntil { await harness.jira.catalogPulls.count == 1 }

    await harness.jira.setHoldPulls(false)
    try await waitUntil {
        try await harness.session.state().catalog.rows.first?.title == "A different recent title"
    }
    let refreshed = try await harness.session.state()
    #expect(refreshed.catalog.rows.first?.key == TicketKey("FAK-400"))
    #expect(!catalogText(refreshed.catalog).contains("Body of FAK-400 must not reach Generate"))
}

@Test func laterOpenServesLastCatalogPullWhenJiraIsUnreachable() async throws {
    let harness = Harness()
    await harness.jira.seed(
        epics: [
            SeededEpic(
                key: "FAK-100",
                name: "Warehouse picking",
                status: "In Progress",
                description: "Epic Scope that must stay out of the Catalog"
            )
        ],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: ["picking"],
                parentEpicKey: "FAK-100",
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_000),
                body: "FAK-231 body must not reach Generate",
                comments: []
            )
        ],
        componentNames: ["Pick App"]
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    await harness.jira.setUnreachable(true)

    let restarted = harness.reopen()
    _ = try await restarted.perform(.typeBrainDump(StoryReply.brainDump))
    let state = try await restarted.perform(.generate)

    #expect(state.catalog.epics.map(\.name) == ["Warehouse picking"])
    let row = try #require(state.catalog.rows.first)
    #expect(row.key == TicketKey("FAK-231"))
    #expect(row.title == "Scan tote before pick")
    #expect(state.catalog.componentNames == ["Pick App"])

    let requests = await harness.model.completeRequests
    let sent = try #require(requests.dropLast().last?.system)
    #expect(sent.contains("Scan tote before pick"))
    #expect(!sent.contains("FAK-231 body must not reach Generate"))
}

@Test func generateSendsCatalogContextToTheModelAndNotAnotherIssueBody() async throws {
    let harness = Harness(terms: ["bin", "pick screen"])
    let otherIssueBody =
        "Steps to reproduce: open the pick screen. This is FAK-231's body and is Scope."
    let otherIssueComment = "The cause is a race in BinScanner."
    let epicDescription = "Epic Scope: rebuild the warehouse pick path."
    await harness.jira.seed(
        epics: [
            SeededEpic(
                key: "FAK-100",
                name: "Warehouse picking",
                status: "In Progress",
                description: epicDescription
            )
        ],
        issues: [
            SeededIssue(
                key: "FAK-231",
                title: "Scan tote before pick",
                jiraIssueType: "Story",
                labels: ["picking"],
                parentEpicKey: "FAK-100",
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_000),
                body: otherIssueBody,
                comments: [otherIssueComment]
            )
        ],
        componentNames: ["Pick App"]
    )

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let state = try await harness.session.perform(.generate)

    #expect(state.catalog.epics == [
        CatalogEpic(key: TicketKey("FAK-100"), name: "Warehouse picking", status: "In Progress")
    ])
    #expect(state.catalog.componentNames == ["Pick App"])
    let row = try #require(state.catalog.rows.first)
    #expect(row.key == TicketKey("FAK-231"))
    #expect(row.title == "Scan tote before pick")
    #expect(row.jiraIssueType == "Story")
    #expect(row.labels == ["picking"])
    #expect(row.parentEpicKey == TicketKey("FAK-100"))
    #expect(row.status == "To Do")

    let requests = await harness.model.completeRequests
    #expect(requests.count == 2)
    let generateSystem = requests[0].system
    #expect(requests[0].user == StoryReply.brainDump)
    #expect(generateSystem.contains("FAK-100"))
    #expect(generateSystem.contains("Warehouse picking"))
    #expect(generateSystem.contains("In Progress"))
    #expect(generateSystem.contains("FAK-231"))
    #expect(generateSystem.contains("Scan tote before pick"))
    #expect(generateSystem.contains("picking"))
    #expect(generateSystem.contains("Pick App"))
    #expect(generateSystem.contains("bin"))
    #expect(generateSystem.contains("pick screen"))
    #expect(generateSystem.contains("Never invent Scope"))
    #expect(!generateSystem.contains(otherIssueBody))
    #expect(!generateSystem.contains(otherIssueComment))
    #expect(!generateSystem.contains(epicDescription))

    #expect(requests[1].user == StoryReply.firstPassDescription)
    #expect(requests[1].system.contains("FAK-231"))
    #expect(requests[1].system.contains("bin"))
    #expect(requests[1].system.contains("pick screen"))
    #expect(!requests[1].system.contains(otherIssueBody))
    #expect(!requests[1].user.contains(StoryReply.brainDump))
}

@Test func unreachableJiraWithNoPriorPullLeavesEmptyCatalogAndGenerateStillRuns() async throws {
    let harness = Harness()
    await harness.jira.setUnreachable(true)
    await harness.jira.seed(
        epics: [
            SeededEpic(
                key: "FAK-100",
                name: "Warehouse picking",
                status: "In Progress",
                description: "must not arrive; the pull never succeeds"
            )
        ],
        issues: [],
        componentNames: ["Pick App"]
    )

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let state = try await harness.session.perform(.generate)

    let draft = try #require(state.draft)
    #expect(draft.ticketType == .story)
    #expect(state.catalog.epics.isEmpty)
    #expect(state.catalog.rows.isEmpty)
    #expect(state.catalog.componentNames.isEmpty)

    let requests = await harness.model.completeRequests
    #expect(requests.count == 2)
    #expect(requests[0].system.contains("Catalog"))
    #expect(!requests[0].system.contains("Warehouse picking"))
    #expect(requests[0].user == StoryReply.brainDump)
}

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
    #expect(state.duplicateInterrupt == nil)
    #expect(state.related.isEmpty)

    let requests = await harness.model.completeRequests
    #expect(requests.count == 2)
    #expect(requests[0].user == StoryReply.brainDump)
    #expect(!requests[0].system.contains("FAK-"))
    #expect(requests[0].system.contains("Never invent Scope"))

    #expect(requests[1].user == StoryReply.firstPassDescription)
    #expect(requests[1].system.contains("Never invent Scope"))
}

@Test func restartingSessionShowsTheInProgressDraftFromDisk() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let original = try #require(generated.draft)

    let restarted = harness.reopen()
    let state = try await restarted.state()
    let draft = try #require(state.draft)

    #expect(draft.id == original.id)
    #expect(draft.ticketType == .story)
    #expect(draft.title == StoryReply.title)
    #expect(draft.shortLabel == StoryReply.shortLabel)
    #expect(draft.description == original.description)
    #expect(draft.key == nil)
}

@Test func restartingSessionShowsTheCurrentDraftNotAnOrphanFromAnEarlierGenerate() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let first = try await harness.session.perform(.generate)
    let firstId = try #require(first.draft).id

    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: "As a picker I want a second Generate so that the Draft is revised",
            shortLabel: "second generate",
            description: "Revised description.",
            openQuestions: []
        )
    )
    let second = try await harness.session.perform(.generate)
    let current = try #require(second.draft)
    #expect(current.id == firstId)
    #expect(current.title == "As a picker I want a second Generate so that the Draft is revised")

    let restarted = harness.reopen()
    let state = try await restarted.state()
    let draft = try #require(state.draft)
    #expect(draft.id == current.id)
    #expect(draft.title == current.title)
}

@Test func submitAfterRestartCreatesTheTicketOnTheSameDraft() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let original = try #require(generated.draft)

    let restarted = harness.reopen()
    let state = try await restarted.perform(.submit)
    let draft = try #require(state.draft)

    #expect(draft.id == original.id)
    #expect(draft.key == TicketKey("FAK-1"))
    #expect(draft.title == StoryReply.title)
    #expect(state.catalog.rows[0].shortLabel == StoryReply.shortLabel)
    #expect(state.catalog.rows[0].ticketType == .story)

    let created = await harness.jira.created
    #expect(created.count == 1)
    #expect(created[0].title == StoryReply.title)
}

@Test func restartAfterSubmitDoesNotRestoreTheUploadQueueAsAnEditor() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    _ = try await harness.session.perform(.submit)

    let restarted = harness.reopen()
    let state = try await restarted.state()
    #expect(state.draft == nil)
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
    #expect(ticket.jiraIssueType == "Task")
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

@Test func failedGenerateLeavesTheDraftAndRetrySucceeds() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    await harness.model.setFailGenerate(true)
    let failed = try await harness.session.perform(.generate)
    #expect(failed.draft == nil)
    #expect(failed.field == StoryReply.brainDump)
    #expect(await harness.model.completeRequests.isEmpty)

    await harness.model.setFailGenerate(false)
    let retried = try await harness.session.perform(.generate)
    let draft = try #require(retried.draft)
    #expect(draft.title == StoryReply.title)
    #expect(draft.description.contains(StoryReply.definitionOfDone))
    #expect(await harness.model.completeRequests.count == 2)
}

@Test func failedGenerateLeavesAnExistingDraftAndRetryRevisesIt() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let first = try await harness.session.perform(.generate)
    let original = try #require(first.draft)

    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: "As a picker I want a retry so that a failed Generate is not data loss",
            shortLabel: "retry after fail",
            description: "Revised after the model recovered.",
            openQuestions: []
        )
    )
    await harness.model.setFailGenerate(true)
    let failed = try await harness.session.perform(.generate)
    #expect(failed.draft?.id == original.id)
    #expect(failed.draft?.title == original.title)
    #expect(failed.draft?.description == original.description)

    await harness.model.setFailGenerate(false)
    let retried = try await harness.session.perform(.generate)
    #expect(retried.draft?.id == original.id)
    #expect(
        retried.draft?.title
            == "As a picker I want a retry so that a failed Generate is not data loss"
    )
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

private let firstLaunchSettings = Settings(
    site: "faktion.atlassian.net",
    email: "pm@faktion.com",
    provider: "openai",
    modelId: "gpt-5.6-luna"
)

private let firstLaunchCredentials = Session.Intent.saveCredentials(
    firstLaunchSettings,
    jiraToken: "jira-secret",
    modelKey: "model-secret"
)

private func catalogText(_ catalog: Catalog) -> String {
    let epics = catalog.epics.map { "\($0.key.value) \($0.name) \($0.status)" }.joined()
    let rows = catalog.rows.map { row in
        let parent = row.parentEpicKey?.value ?? ""
        return "\(row.key.value) \(row.title) \(row.jiraIssueType) \(row.labels.joined()) \(parent) \(row.status)"
    }.joined()
    return epics + rows + catalog.componentNames.joined()
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    _ predicate: () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting for Catalog refresh")
}

private struct DiskCatalog: Codable {
    var pulledAt: Date?
    var catalog: Catalog
}

private struct DiskSidecar: Codable {
    var ticketType: TicketType
    var title: String
    var shortLabel: String
    var openQuestions: [String]
    var key: String?
}

private enum BugReply {
    static let title = "Pick screen does not show a bin scan error"
    static let shortLabel = "bin scan error missing"
    static let firstPassDescription = """
        The pick screen does not show an error when a bin scan fails.

        1. Open a pick
        2. Scan a bin that fails
        3. Watch the pick screen

        **Expected:** a blocking error
        **Actual:** the pick continues
        **Environment:** warehouse iPad
        """
    static let definitionOfDone = "Pick screen shows a blocking error when a bin scan fails"
    static let brainDump =
        "the pick screen doesn't show anything when the bin scan fails, they just keep picking"
}

private enum ChoreReply {
    static let title = "Upgrade the pick-screen scanner SDK"
    static let shortLabel = "upgrade scanner SDK"
    static let firstPassDescription =
        "Bump the scanner SDK so pickers can scan the new bin labels."
    static let brainDump =
        "upgrade the scanner SDK on the pick screen so it can read the new bin labels"
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
    let transcriber: FakeTranscriber
    let secrets: FakeSecrets
    let root: URL
    let project: Project
    let session: Session

    var settingsURL: URL {
        root.appending(component: "settings.json")
    }

    var projectJSONURL: URL {
        root
            .appending(component: "projects")
            .appending(component: "FAK")
            .appending(component: "project.json")
    }

    init(
        ticketTypeMapping: [TicketType: String] = [
            .story: "Story",
            .bug: "Bug",
            .chore: "Chore",
        ],
        terms: [String] = [],
        seedProject: Bool = true,
        compileFinished: Bool = true
    ) {
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
        let transcriber = FakeTranscriber(compileFinished: compileFinished)
        let secrets = FakeSecrets()
        let root = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        let project = Project(key: "FAK", ticketTypeMapping: ticketTypeMapping, terms: terms)
        self.model = model
        self.jira = jira
        self.transcriber = transcriber
        self.secrets = secrets
        self.root = root
        self.project = project
        self.session = Session(
            applicationSupport: root,
            model: model,
            jira: jira,
            transcriber: transcriber,
            secrets: secrets
        )
        if seedProject {
            try! writeProject(project)
        }
    }

    func reopen() -> Session {
        Session(
            applicationSupport: root,
            model: model,
            jira: jira,
            transcriber: transcriber,
            secrets: secrets
        )
    }

    func draftFolder(id: String) -> URL {
        root
            .appending(component: "projects")
            .appending(component: "FAK")
            .appending(component: "drafts")
            .appending(component: id)
    }

    func generateStory(openQuestions: [String] = []) async throws -> Session.State {
        await model.replaceReply(
            GenerateReply(
                ticketType: .story,
                title: StoryReply.title,
                shortLabel: StoryReply.shortLabel,
                description: StoryReply.firstPassDescription,
                openQuestions: openQuestions
            )
        )
        _ = try await session.perform(.typeBrainDump(StoryReply.brainDump))
        return try await session.perform(.generate)
    }

    func writeProject(_ project: Project) throws {
        let folder = root
            .appending(component: "projects")
            .appending(component: project.key)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let file = DiskProject(
            ticketTypeMapping: project.ticketTypeMapping,
            terms: project.terms
        )
        try encoder.encode(file).write(to: folder.appending(component: "project.json"))
    }

    func writeCatalog(
        pulledAt: Date,
        epics: [CatalogEpic],
        rows: [CatalogRow],
        componentNames: [String]
    ) throws {
        let folder = root
            .appending(component: "projects")
            .appending(component: "FAK")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let file = DiskCatalog(
            pulledAt: pulledAt,
            catalog: Catalog(epics: epics, rows: rows, componentNames: componentNames)
        )
        try encoder.encode(file).write(to: folder.appending(component: "catalog.json"))
    }

    func writeDraft(
        id: String,
        ticketType: TicketType,
        title: String,
        shortLabel: String,
        description: String
    ) throws {
        let folder = draftFolder(id: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sidecar = DiskSidecar(
            ticketType: ticketType,
            title: title,
            shortLabel: shortLabel,
            openQuestions: [],
            key: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(sidecar).write(to: folder.appending(component: "draft.json"))
        try description.write(
            to: folder.appending(component: "description.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct DiskProject: Codable {
    var ticketTypeMapping: [TicketType: String]
    var terms: [String]
}
