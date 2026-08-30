import Foundation
import Testing
import Fakthis

@Test func namingABatchFromTheControlMakesTwoSiblingsAndDoesNotCallTheModel() async throws {
    let harness = Harness()
    let state = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let batch = try #require(state.batch)
    #expect(batch.name == "Checkout totals")
    #expect(batch.siblings.map(\.shortLabel) == ["scan bin", "export totals"])
    #expect(batch.siblings.count == 2)
    #expect(batch.focusedDraftId == batch.siblings[0].id)
    #expect(state.draft?.id == batch.siblings[0].id)
    #expect(state.draft?.shortLabel == "scan bin")
    #expect(batch.blocks == batch.siblings.map(\.id))
    #expect(await harness.model.completeRequests.isEmpty)
    #expect(await harness.jira.created.isEmpty)
}

@Test func namingABatchRequiresAtLeastTwoDrafts() async throws {
    let harness = Harness()
    let state = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin"])
    )
    #expect(state.batch == nil)
    #expect(state.draft == nil)
    #expect(await harness.model.completeRequests.isEmpty)
}

@Test func generateOnABatchWritesTheFocusedSiblingAndSendsSiblingsAsContext() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let secondId = try #require(named.batch?.siblings[1].id)

    let generated = try await harness.session.perform(.generate)
    let draft = try #require(generated.draft)
    #expect(draft.id == firstId)
    #expect(draft.title == StoryReply.title)
    #expect(draft.shortLabel == StoryReply.shortLabel)
    #expect(generated.batch?.siblings[0].shortLabel == StoryReply.shortLabel)
    #expect(generated.batch?.siblings[1].id == secondId)
    #expect(generated.batch?.siblings[1].shortLabel == "export totals")

    let siblingSidecar = try JSONDecoder().decode(
        DiskSidecar.self,
        from: Data(
            contentsOf: harness.draftFolder(id: secondId).appending(component: "draft.json")
        )
    )
    #expect(siblingSidecar.title == "")
    #expect(siblingSidecar.shortLabel == "export totals")

    let request = try #require(await harness.model.completeRequests.first)
    #expect(request.user.contains(StoryReply.brainDump))
    #expect(request.user.contains("Draft 1 of 2"))
    #expect(request.user.contains("scan bin"))
    #expect(request.user.contains("export totals"))
    #expect(request.system.contains("Never invent Scope"))
}

@Test func namingABatchAfterADraftExistsMakesItDraft1AndOffersRegenerate() async throws {
    let harness = Harness()
    let generated = try await harness.generateStory()
    let original = try #require(generated.draft)
    let requestsBefore = await harness.model.completeRequests.count
    #expect(generated.batch == nil)

    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let batch = try #require(named.batch)
    #expect(batch.siblings[0].id == original.id)
    #expect(named.draft?.id == original.id)
    #expect(named.draft?.title == original.title)
    #expect(named.draft?.description == original.description)
    #expect(batch.offerRegenerateDraft1 == true)
    #expect(batch.siblings.count == 2)
    #expect(batch.siblings[1].shortLabel == "export totals")
    #expect(batch.focusedDraftId == original.id)
    #expect(await harness.model.completeRequests.count == requestsBefore)
}

@Test func generateOnDraft1AcceptsTheRegenerateOffer() async throws {
    let harness = Harness()
    let generated = try await harness.generateStory()
    let originalDescription = try #require(generated.draft?.description)
    _ = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: StoryReply.title,
            shortLabel: "scan bin",
            description: "Scope that belongs to this sibling only.",
            openQuestions: []
        )
    )
    let regenerated = try await harness.session.perform(.generate)
    #expect(regenerated.draft?.description.contains("Scope that belongs to this sibling only.") == true)
    #expect(regenerated.draft?.description != originalDescription)
    #expect(regenerated.batch?.offerRegenerateDraft1 == false)
}

@Test func dismissingTheRegenerateOfferLeavesDraft1Unchanged() async throws {
    let harness = Harness()
    let generated = try await harness.generateStory()
    let original = try #require(generated.draft)
    let requestsBefore = await harness.model.completeRequests.count
    _ = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let dismissed = try await harness.session.perform(.dismissRegenerateOffer)
    #expect(dismissed.batch?.offerRegenerateDraft1 == false)
    #expect(dismissed.draft?.id == original.id)
    #expect(dismissed.draft?.description == original.description)
    #expect(await harness.model.completeRequests.count == requestsBefore)
}

@Test func focusingASiblingMakesGenerateWriteThatDraftOnly() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let secondId = try #require(named.batch?.siblings[1].id)
    let first = try await harness.session.perform(.generate)
    #expect(first.draft?.id == firstId)
    #expect(first.draft?.title == StoryReply.title)

    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: "export totals",
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    let focused = try await harness.session.perform(.focusDraft(secondId))
    #expect(focused.draft?.id == secondId)
    #expect(focused.batch?.focusedDraftId == secondId)
    #expect(focused.draft?.title == "")

    let second = try await harness.session.perform(.generate)
    #expect(second.draft?.id == secondId)
    #expect(second.draft?.title == ChoreReply.title)
    #expect(second.draft?.ticketType == .chore)
    #expect(second.batch?.siblings[0].id == firstId)
    #expect(second.batch?.siblings[1].shortLabel == "export totals")

    let firstSidecar = try JSONDecoder().decode(
        DiskSidecar.self,
        from: Data(contentsOf: harness.draftFolder(id: firstId).appending(component: "draft.json"))
    )
    #expect(firstSidecar.title == StoryReply.title)

    let requests = await harness.model.completeRequests
    let siblingGenerate = try #require(requests.first { $0.user.contains("Draft 2 of 2") })
    #expect(siblingGenerate.user.contains(StoryReply.brainDump))
    #expect(siblingGenerate.user.contains("export totals"))
}

@Test func aDumpTakeStillAppendsAfterNamingABatchAndBeforeGenerate() async throws {
    let harness = Harness()
    await harness.transcriber.enqueueTake("we need pickers to scan the bin")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    _ = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    await harness.transcriber.enqueueTake("and export the totals")
    _ = try await harness.session.perform(.startListening)
    let committed = try await harness.session.perform(.stopListening)
    #expect(committed.field == "we need pickers to scan the bin and export the totals")
    #expect(await harness.model.completeRequests.isEmpty)
}

@Test func aSiblingGenerateAfterMidChatConversionUsesTheDumpAndTheNamingTurn() async throws {
    let harness = Harness()
    _ = try await harness.generateStory()
    _ = try await harness.session.perform(
        .typeBrainDump("that's three tickets: scan bin and export totals")
    )
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let secondId = try #require(named.batch?.siblings[1].id)
    _ = try await harness.session.perform(.focusDraft(secondId))
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: "export totals",
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.generate)
    let request = try #require(
        await harness.model.completeRequests.first { $0.user.contains("Draft 2 of 2") }
    )
    #expect(request.user.contains(StoryReply.brainDump))
    #expect(request.user.contains("that's three tickets: scan bin and export totals"))
    #expect(request.user.contains("export totals"))
}

@Test func aChatAnswerStaysWithTheFocusedSibling() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let secondId = try #require(named.batch?.siblings[1].id)
    _ = try await harness.session.perform(.generate)
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: "export totals",
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.focusDraft(secondId))
    _ = try await harness.session.perform(.generate)

    _ = try await harness.session.perform(.focusDraft(firstId))
    _ = try await harness.session.perform(.typeBrainDump("show a blocking error on the pick screen"))
    let onChore = try await harness.session.perform(.focusDraft(secondId))
    #expect(onChore.field != "show a blocking error on the pick screen")
    _ = try await harness.session.perform(.typeBrainDump("bump the scanner SDK"))
    let back = try await harness.session.perform(.focusDraft(firstId))
    #expect(back.field == "show a blocking error on the pick screen")
}

@Test func sendRevisesOnlyTheFocusedBatchSibling() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let secondId = try #require(named.batch?.siblings[1].id)
    _ = try await harness.session.perform(.generate)
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: "export totals",
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.focusDraft(secondId))
    _ = try await harness.session.perform(.generate)

    _ = try await harness.session.perform(.focusDraft(firstId))
    _ = try await harness.session.perform(.typeBrainDump("show a blocking error on the pick screen"))
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: StoryReply.title,
            shortLabel: StoryReply.shortLabel,
            description: "Revised pick-screen Scope only.",
            openQuestions: []
        )
    )
    let sent = try await harness.session.perform(.send)
    #expect(sent.draft?.id == firstId)
    #expect(sent.draft?.description.contains("Revised pick-screen Scope only.") == true)

    let siblingSidecar = try JSONDecoder().decode(
        DiskSidecar.self,
        from: Data(contentsOf: harness.draftFolder(id: secondId).appending(component: "draft.json"))
    )
    #expect(siblingSidecar.title == ChoreReply.title)

    let request = try #require(
        await harness.model.completeRequests.last { $0.user.contains("Chat answer:") }
    )
    #expect(request.user.contains("Draft 1 of 2"))
}

@Test func addingADraftToABatchAppendsAnEmptySibling() async throws {
    let harness = Harness()
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let focused = try #require(named.batch?.focusedDraftId)
    let added = try await harness.session.perform(.addDraft(shortLabel: "upgrade SDK"))
    let batch = try #require(added.batch)
    #expect(batch.siblings.map(\.shortLabel) == ["scan bin", "export totals", "upgrade SDK"])
    #expect(batch.siblings.count == 3)
    #expect(batch.blocks == batch.siblings.map(\.id))
    #expect(batch.focusedDraftId == focused)
    #expect(added.draft?.id == focused)
    let newId = batch.siblings[2].id
    let sidecar = try JSONDecoder().decode(
        DiskSidecar.self,
        from: Data(contentsOf: harness.draftFolder(id: newId).appending(component: "draft.json"))
    )
    #expect(sidecar.title == "")
    #expect(sidecar.shortLabel == "upgrade SDK")
    #expect(await harness.model.completeRequests.isEmpty)
}

@Test func removingASiblingDeletesItAndKeepsTheBatch() async throws {
    let harness = Harness()
    let named = try await harness.session.perform(
        .nameBatch(
            name: "Checkout totals",
            shortLabels: ["scan bin", "export totals", "upgrade SDK"]
        )
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let removedId = try #require(named.batch?.siblings[1].id)
    let lastId = try #require(named.batch?.siblings[2].id)
    let removed = try await harness.session.perform(.removeDraft(removedId))
    let batch = try #require(removed.batch)
    #expect(batch.siblings.map(\.id) == [firstId, lastId])
    #expect(batch.blocks == [firstId, lastId])
    #expect(removed.draft?.id == firstId)
    #expect(
        !FileManager.default.fileExists(atPath: harness.draftFolder(id: removedId).path)
    )
}

@Test func removingTheLastExtraDissolvesTheBatchIntoTheRemainingDraft() async throws {
    let harness = Harness()
    let generated = try await harness.generateStory()
    let original = try #require(generated.draft)
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let extraId = try #require(named.batch?.siblings[1].id)
    let dissolved = try await harness.session.perform(.removeDraft(extraId))
    #expect(dissolved.batch == nil)
    #expect(dissolved.draft?.id == original.id)
    #expect(dissolved.draft?.title == original.title)
    #expect(
        !FileManager.default.fileExists(atPath: harness.draftFolder(id: extraId).path)
    )
}

@Test func renamingASiblingEditsTheListWithoutCallingTheModel() async throws {
    let harness = Harness()
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let renamed = try await harness.session.perform(
        .renameSibling(id: firstId, shortLabel: "scan tote")
    )
    #expect(renamed.batch?.siblings[0].shortLabel == "scan tote")
    #expect(renamed.draft?.shortLabel == "scan tote")
    #expect(await harness.model.completeRequests.isEmpty)
}

@Test func aBatchTakesOneExistingEpicAsDefaultOverrideablePerDraft() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [
            CatalogEpic(key: TicketKey("FAK-100"), name: "Warehouse picking", status: "In Progress"),
            CatalogEpic(key: TicketKey("FAK-200"), name: "Exports", status: "To Do"),
        ],
        rows: [],
        componentNames: []
    )
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let secondId = try #require(named.batch?.siblings[1].id)

    let withDefault = try await harness.session.perform(.setDefaultEpic(TicketKey("FAK-100")))
    #expect(withDefault.batch?.defaultEpicKey == TicketKey("FAK-100"))

    let invented = try await harness.session.perform(.setDefaultEpic(TicketKey("FAK-999")))
    #expect(invented.batch?.defaultEpicKey == TicketKey("FAK-100"))

    let overridden = try await harness.session.perform(
        .overrideEpic(id: secondId, TicketKey("FAK-200"))
    )
    #expect(overridden.batch?.siblings[0].id == firstId)
    #expect(overridden.batch?.siblings[0].epicKey == nil)
    #expect(overridden.batch?.siblings[1].epicKey == TicketKey("FAK-200"))

    let cleared = try await harness.session.perform(.overrideEpic(id: secondId, nil))
    #expect(cleared.batch?.siblings[1].epicKey == nil)
    #expect(cleared.batch?.defaultEpicKey == TicketKey("FAK-100"))
}

@Test func blocksFollowNamedOrderAndAreEditableAndClearable() async throws {
    let harness = Harness()
    let named = try await harness.session.perform(
        .nameBatch(
            name: "Checkout totals",
            shortLabels: ["scan bin", "export totals", "upgrade SDK"]
        )
    )
    let ids = try #require(named.batch?.siblings.map(\.id))
    #expect(named.batch?.blocks == ids)

    let reordered = try await harness.session.perform(.setBlocks([ids[1], ids[0], ids[2]]))
    #expect(reordered.batch?.blocks == [ids[1], ids[0], ids[2]])
    #expect(reordered.batch?.siblings.map(\.id) == ids)

    let independent = try await harness.session.perform(.clearBlocks)
    #expect(independent.batch?.blocks == [])
    #expect(independent.batch?.siblings.count == 3)
}

@Test func textMaterialIsVisibleToEveryBatchGenerate() async throws {
    let harness = Harness()
    let email = "From: client@acme.com\nWe need pickers to scan the bin before they pick."
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "client-email.txt", mimeType: "text/plain", data: Data(email.utf8))
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let secondId = try #require(named.batch?.siblings[1].id)
    _ = try await harness.session.perform(.generate)
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: "export totals",
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.focusDraft(secondId))
    _ = try await harness.session.perform(.generate)

    let generateRequests = await harness.model.completeRequests.filter {
        $0.user.contains("Draft ")
    }
    #expect(generateRequests.count == 2)
    for request in generateRequests {
        #expect(request.user.contains(email))
        #expect(request.user.contains("client-email.txt"))
    }
}

@Test func screenshotsDefaultToTheFocusedDraftAndCanBeAssignedToMore() async throws {
    let harness = Harness()
    let png = Data("fake-png-bytes".utf8)
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let secondId = try #require(named.batch?.siblings[1].id)
    _ = try await harness.session.perform(
        .attachMaterial(Material(filename: "pick.png", mimeType: "image/png", data: png))
    )
    _ = try await harness.session.perform(.generate)
    let firstGenerate = try #require(
        await harness.model.completeRequests.first { $0.user.contains("Draft 1 of 2") }
    )
    #expect(firstGenerate.screenshots.map(\.filename) == ["pick.png"])

    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: "export totals",
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.focusDraft(secondId))
    _ = try await harness.session.perform(.generate)
    let secondGenerate = try #require(
        await harness.model.completeRequests.first { $0.user.contains("Draft 2 of 2") }
    )
    #expect(secondGenerate.screenshots.isEmpty)

    _ = try await harness.session.perform(
        .assignMedia(filename: "pick.png", draftIds: [firstId, secondId])
    )
    _ = try await harness.session.perform(.generate)
    let assignedGenerate = try #require(
        await harness.model.completeRequests.last { $0.user.contains("Draft 2 of 2") }
    )
    #expect(assignedGenerate.screenshots.map(\.filename) == ["pick.png"])
}

@Test func submitCreatesABatchInBlocksOrderAndWritesLinksWhenBothKeysExist() async throws {
    let harness = Harness()
    let ids = try await harness.generateTwoSiblingBatch()
    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.batch == nil)
    #expect(submitted.draft?.key == TicketKey("FAK-2"))

    let created = await harness.jira.created
    #expect(created.map(\.title) == [StoryReply.title, ChoreReply.title])
    let links = await harness.jira.blocksLinks
    #expect(links.count == 1)
    #expect(links[0].blocker == TicketKey("FAK-1"))
    #expect(links[0].blocked == TicketKey("FAK-2"))
    #expect(submitted.catalog.rows.map(\.key) == [TicketKey("FAK-1"), TicketKey("FAK-2")])
    #expect(
        !FileManager.default.fileExists(atPath: harness.draftFolder(id: ids.0).path)
    )
    #expect(
        !FileManager.default.fileExists(atPath: harness.draftFolder(id: ids.1).path)
    )
}

@Test func submitStopsOnTheFirstCreateFailureAndRetryCreatesTheRest() async throws {
    let harness = Harness()
    _ = try await harness.generateTwoSiblingBatch()
    await harness.jira.setFailOnCreate(2)
    let failed = try await harness.session.perform(.submit)
    #expect(await harness.jira.created.count == 1)
    #expect(failed.batch?.siblings[0].key == TicketKey("FAK-1"))
    #expect(failed.batch?.siblings[1].key == nil)
    #expect(await harness.jira.blocksLinks.isEmpty)

    await harness.jira.setFailOnCreate(nil)
    let retried = try await harness.session.perform(.submit)
    #expect(await harness.jira.created.map(\.title) == [StoryReply.title, ChoreReply.title])
    #expect(retried.batch == nil)
    #expect(retried.catalog.rows.map(\.key) == [TicketKey("FAK-1"), TicketKey("FAK-2")])
    let links = await harness.jira.blocksLinks
    #expect(links.count == 1)
    #expect(links[0].blocker == TicketKey("FAK-1"))
    #expect(links[0].blocked == TicketKey("FAK-2"))
}

@Test func restartAfterAPartialBatchSubmitRetriesTheRestWithoutRecreating() async throws {
    let harness = Harness()
    _ = try await harness.generateTwoSiblingBatch()
    await harness.jira.setFailOnCreate(2)
    _ = try await harness.session.perform(.submit)
    #expect(await harness.jira.created.count == 1)

    let restarted = harness.reopen()
    await harness.jira.setFailOnCreate(nil)
    let retried = try await restarted.perform(.submit)
    #expect(await harness.jira.created.map(\.title) == [StoryReply.title, ChoreReply.title])
    #expect(retried.catalog.rows.map(\.key) == [TicketKey("FAK-1"), TicketKey("FAK-2")])
    let links = await harness.jira.blocksLinks
    #expect(links.count == 1)
    #expect(links[0].blocker == TicketKey("FAK-1"))
    #expect(links[0].blocked == TicketKey("FAK-2"))
}

@Test func submitUsesTheDraftEpicOrTheBatchDefault() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [
            CatalogEpic(key: TicketKey("FAK-100"), name: "Warehouse picking", status: "In Progress"),
            CatalogEpic(key: TicketKey("FAK-200"), name: "Exports", status: "To Do"),
        ],
        rows: [],
        componentNames: []
    )
    let named = try await harness.generateTwoSiblingBatch()
    _ = try await harness.session.perform(.setDefaultEpic(TicketKey("FAK-100")))
    _ = try await harness.session.perform(
        .overrideEpic(id: named.1, TicketKey("FAK-200"))
    )
    _ = try await harness.session.perform(.submit)
    let created = await harness.jira.created
    #expect(created[0].parentKey == TicketKey("FAK-100"))
    #expect(created[1].parentKey == TicketKey("FAK-200"))
}

@Test func clearingBlocksSubmitsTheBatchWithoutLinks() async throws {
    let harness = Harness()
    _ = try await harness.generateTwoSiblingBatch()
    _ = try await harness.session.perform(.clearBlocks)
    _ = try await harness.session.perform(.submit)
    #expect(await harness.jira.created.count == 2)
    #expect(await harness.jira.blocksLinks.isEmpty)
}

@Test func batchSiblingsAreNotDuplicatesOfEachOther() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "scan bin location"])
    )
    let secondId = try #require(named.batch?.siblings[1].id)
    _ = try await harness.session.perform(.generate)
    _ = try await harness.session.perform(.focusDraft(secondId))
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: StoryReply.title,
            shortLabel: StoryReply.shortLabel,
            description: StoryReply.firstPassDescription,
            openQuestions: []
        )
    )
    let second = try await harness.session.perform(.generate)
    #expect(second.duplicateInterrupt == nil)
    #expect(second.batch?.duplicates.isEmpty == true)
}

@Test func aBatchHasOneDuplicateInterruptListingWhichDraftsHitWhichKeys() async throws {
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
    let ids = try await harness.generateTwoSiblingBatch()
    let state = try await harness.session.state()
    #expect(state.duplicateInterrupt == nil)
    let duplicates = try #require(state.batch?.duplicates)
    #expect(duplicates.count == 1)
    #expect(duplicates[0].draftId == ids.0)
    #expect(duplicates[0].hit.key == TicketKey("FAK-231"))
    #expect(duplicates[0].shortLabel == StoryReply.shortLabel)

    let dismissed = try await harness.session.perform(.dismissDuplicate)
    #expect(dismissed.batch?.duplicates.isEmpty == true)
    #expect(dismissed.duplicateInterrupt == nil)

    let submitted = try await harness.session.perform(.submit)
    #expect(await harness.jira.created.count == 2)
    #expect(submitted.batch == nil)
}

@Test func restartingSessionRestoresTheBatchAndFocusedDraft() async throws {
    let harness = Harness()
    let ids = try await harness.generateTwoSiblingBatch()
    let restarted = harness.reopen()
    let state = try await restarted.state()
    let batch = try #require(state.batch)
    #expect(batch.siblings.map(\.id) == [ids.0, ids.1])
    #expect(batch.focusedDraftId == ids.1)
    #expect(state.draft?.id == ids.1)
    #expect(state.draft?.title == ChoreReply.title)
    #expect(batch.blocks == [ids.0, ids.1])
}

@Test func assignedMediaUploadsToEachSiblingOnSubmit() async throws {
    let harness = Harness()
    let png = Data("fake-png-bytes".utf8)
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let secondId = try #require(named.batch?.siblings[1].id)
    _ = try await harness.session.perform(
        .attachMaterial(Material(filename: "pick.png", mimeType: "image/png", data: png))
    )
    _ = try await harness.session.perform(.generate)
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: "export totals",
            description: ChoreReply.firstPassDescription,
            openQuestions: []
        )
    )
    _ = try await harness.session.perform(.focusDraft(secondId))
    _ = try await harness.session.perform(.generate)
    _ = try await harness.session.perform(
        .assignMedia(filename: "pick.png", draftIds: [firstId, secondId])
    )
    _ = try await harness.session.perform(.submit)
    let uploads = await harness.jira.uploaded
    #expect(uploads.map(\.filename) == ["pick.png", "pick.png"])
    #expect(Set(uploads.map(\.key.value)) == ["FAK-1", "FAK-2"])
}

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
    // Generate spent the field: what the PM said is in the conversation, and the composer is
    // ready for the answer to the question that came back.
    #expect(generated.field.isEmpty)
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
    #expect(await harness.transcriber.boostLists == [[]])
}

@Test func bothVoiceTiersPassProjectTermsOnTheBatchPass() async throws {
    let harness = Harness(terms: ["bin", "pick screen"])
    await harness.transcriber.enqueueTake("scan the bin")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    #expect(await harness.transcriber.boostLists == [["bin", "pick screen"]])

    _ = try await harness.session.perform(.generate)
    await harness.transcriber.enqueueTake("show a blocking error")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    #expect(await harness.transcriber.boostLists == [
        ["bin", "pick screen"],
        ["bin", "pick screen"],
    ])
}

@Test func stopListeningProjectsProjectTermsThenEpicNamesThenComponentsAndNeverTitles() async throws {
    let harness = Harness(terms: ["bin", "SM-A-rt"])
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [
            CatalogEpic(key: TicketKey("FAK-100"), name: "Warehouse picking", status: "In Progress"),
            CatalogEpic(key: TicketKey("FAK-200"), name: "Exports", status: "To Do"),
        ],
        rows: [
            CatalogRow(
                key: TicketKey("FAK-231"),
                title: "This title must not be boosted",
                jiraIssueType: "Story"
            ),
        ],
        componentNames: ["Pick App"]
    )
    await harness.transcriber.enqueueTake("scan the bin")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    #expect(await harness.transcriber.boostLists == [[
        "bin",
        "SM-A-rt",
        "Warehouse picking",
        "Exports",
        "Pick App",
    ]])
}

@Test func transcriberBoostListCapsAtOneHundredKeepingTermsThenEpics() async throws {
    let terms = (1...80).map { "term-\($0)" }
    let harness = Harness(terms: terms)
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: (1...30).map {
            CatalogEpic(key: TicketKey("FAK-\($0)"), name: "epic-\($0)", status: "To Do")
        },
        rows: [],
        componentNames: (1...10).map { "component-\($0)" }
    )
    await harness.transcriber.enqueueTake("scan the bin")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    let passed = try #require(await harness.transcriber.boostLists.first)
    #expect(passed.count == TranscriberBoost.cap)
    #expect(passed.prefix(80) == ArraySlice(terms))
    #expect(Array(passed.dropFirst(80)) == (1...20).map { "epic-\($0)" })
    #expect(!passed.contains("component-1"))
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
    #expect(generated.field.isEmpty)
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
    #expect(generated.field.isEmpty)
    #expect(await harness.model.completeRequests.first?.user == StoryReply.brainDump)
    #expect(await harness.transcriber.boostLists.isEmpty)
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

@Test func confirmingAProjectStoresMappingAndEmptyTermsAndPullsCatalog() async throws {
    let harness = Harness(seedProject: false)
    await harness.jira.seedIssueTypes([
        JiraIssueType(name: "Epic", hierarchyLevel: 1, subtask: false),
        JiraIssueType(name: "Work", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Story", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Bug", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Sub-task", hierarchyLevel: -1, subtask: true),
    ])
    _ = try await harness.session.perform(firstLaunchCredentials)
    let proposal = try await harness.session.perform(.enterProjectKey("FAK"))
    #expect(proposal.textMaterialDisclosure == "Text Material is sent to the model provider.")
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
    #expect(
        generated.structuralWarnings.contains(
            StructuralWarning(field: .title, text: "title does not match the Bug convention")
        )
    )
    #expect(
        generated.structuralWarnings.contains(
            StructuralWarning(field: .description, text: "Bug is missing steps to reproduce")
        )
    )
    #expect(
        generated.structuralWarnings.contains(
            StructuralWarning(field: .description, text: "Bug is missing Expected against Actual")
        )
    )
    #expect(
        generated.structuralWarnings.contains(
            StructuralWarning(field: .description, text: "Bug is missing Environment")
        )
    )

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
    #expect(
        generated.structuralWarnings.contains(
            StructuralWarning(field: .description, text: "description leaves the Markdown vocabulary")
        )
    )
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
    #expect(
        generated.structuralWarnings.contains(
            StructuralWarning(field: .title, text: "title does not match the Chore convention")
        )
    )
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

@Test func aHandEditOfTheDescriptionOffersToRegenerateTheDefinitionOfDoneAndReArms() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    // The agent has just written both passes, so there is nothing outstanding to offer about.
    #expect(!generated.offerRegenerateDefinitionOfDone)
    let description = try #require(generated.draft?.description)

    // Typing raises nothing. A bar that appeared on the first character would push the text
    // down under the cursor while it was still being written.
    let typing = try await harness.session.perform(
        .editDescription(description + "\n\nThe scan is per bin, not per tote.")
    )
    #expect(!typing.offerRegenerateDefinitionOfDone)

    let edited = try await harness.session.perform(.finishEditingDescription)
    #expect(edited.offerRegenerateDefinitionOfDone)

    let kept = try await harness.session.perform(.keepDefinitionOfDone)
    #expect(!kept.offerRegenerateDefinitionOfDone)
    #expect(kept.draft?.description == edited.draft?.description)

    // Focus coming and going without a keystroke is not a hand-edit.
    let idle = try await harness.session.perform(.finishEditingDescription)
    #expect(!idle.offerRegenerateDefinitionOfDone)

    // Re-arms: Keep answers the edit that armed it, not every edit after it.
    _ = try await harness.session.perform(
        .editDescription(description + "\n\nThe scan is per bin.")
    )
    let editedAgain = try await harness.session.perform(.finishEditingDescription)
    #expect(editedAgain.offerRegenerateDefinitionOfDone)
}

@Test func regeneratingTheDefinitionOfDoneReadsOnlyTheDescriptionAboveTheRule() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let description = try #require(generated.draft?.description)
    #expect(description.contains(StoryReply.definitionOfDone))

    let body = StoryReply.firstPassDescription + "\n\nThe scan is per bin, not per tote."
    _ = try await harness.session.perform(
        .editDescription(
            """
            \(body)

            ---

            **Definition of Done:**

            - \(StoryReply.definitionOfDone)
            """
        )
    )
    _ = try await harness.session.perform(.finishEditingDescription)
    await harness.model.replaceDefinitionOfDone(["Each bin is scanned separately"])
    let regenerated = try await harness.session.perform(.regenerateDefinitionOfDone)

    let secondPass = try #require(await harness.model.completeRequests.last)
    #expect(secondPass.user == body)
    #expect(!secondPass.user.contains("Definition of Done"))
    #expect(!secondPass.user.contains(StoryReply.definitionOfDone))

    let after = try #require(regenerated.draft?.description)
    #expect(after.contains("- Each bin is scanned separately"))
    #expect(!after.contains(StoryReply.definitionOfDone))
    #expect(after.contains("The scan is per bin, not per tote."))
    #expect(!regenerated.offerRegenerateDefinitionOfDone)
}

@Test func aFailedRegenerateOfTheDefinitionOfDoneKeepsTheDraftAndLeavesTheOfferStanding()
    async throws
{
    let harness = Harness()
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let description = try #require(generated.draft?.description)
    _ = try await harness.session.perform(
        .editDescription(description + "\n\nThe scan is per bin, not per tote.")
    )
    let edited = try await harness.session.perform(.finishEditingDescription)

    await harness.model.setFailGenerate(true)
    let failed = try await harness.session.perform(.regenerateDefinitionOfDone)
    #expect(failed.draft?.description == edited.draft?.description)
    #expect(failed.offerRegenerateDefinitionOfDone)
    #expect(failed.status == .yourTurn)
}

@Test func draftSignalsCarryTheCatalogMaterialAndUploadFactsAndNeverTheOpenQuestions()
    async throws
{
    let harness = Harness()
    await harness.jira.setAttachmentPolicy(AttachmentPolicy(enabled: true, uploadLimit: 10))
    let attached = try await harness.session.perform(
        .attachMaterial(
            Material(
                filename: "pick.png",
                mimeType: "image/png",
                data: Data("this-screenshot-is-oversize".utf8)
            )
        )
    )
    #expect(
        attached.draftSignals == [DraftSignal(kind: .material, text: "pick.png is oversize")]
    )

    await harness.model.replaceReply(StoryReply.asking("Which bin does a picker scan first?"))
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)

    // The open-questions section **is** its own warning and sits in the description. Repeating
    // it in the gutter would inflate the count by one and say nothing new.
    #expect(generated.draft?.openQuestions.isEmpty == false)
    #expect(!generated.draftSignals.contains { $0.text.contains("question") })
    #expect(generated.draftSignals.map(\.kind) == [.material])
}

@Test func aMaterialWarningThatNamesNoFileStaysInTheGutterAfterSubmit() async throws {
    let harness = Harness()
    await harness.jira.setAttachmentPolicy(AttachmentPolicy(enabled: false, uploadLimit: 0))
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "pick.png", mimeType: "image/png", data: Data("png".utf8))
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    let submitted = try await harness.session.perform(.submit)

    // The site refusing attachments is true whether or not the Ticket exists yet, so it is not
    // replaced by the after-the-fact "was skipped" line the way a warning about one file is.
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(
        submitted.draftSignals.map(\.text) == [
            "attachments are disabled",
            "pick.png was skipped — Jira would not take it.",
        ]
    )
}

@Test func aFailedUploadIsADraftSignalAndNothingInTheGutterBlocksSubmit() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "pick.png", mimeType: "image/png", data: Data("png".utf8))
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    await harness.jira.setFailUploads(true)

    let submitted = try await harness.session.perform(.submit)
    // Submit went through with a signal already resting: the Ticket exists.
    #expect(submitted.draft?.key == TicketKey("FAK-1"))
    #expect(submitted.draftSignals.map(\.kind) == [.upload])
    #expect(submitted.draftSignals.first?.text.contains("pick.png did not upload") == true)

    await harness.jira.setFailUploads(false)
    let retried = try await harness.session.perform(.retryUploads)
    #expect(retried.draftSignals.isEmpty)
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

@Test func attachedMaterialIsOnStateBeforeGenerateAndSurvivesAReopen() async throws {
    let harness = Harness()
    for item in [
        Material(filename: "client-email.txt", mimeType: "text/plain", data: Data("email".utf8)),
        Material(filename: "pick.png", mimeType: "image/png", data: Data("png-bytes".utf8)),
        Material(filename: "repro.mov", mimeType: "video/quicktime", data: Data("mov".utf8)),
    ] {
        _ = try await harness.session.perform(.attachMaterial(item))
    }

    let attached = try await harness.session.state()
    #expect(attached.draft == nil)
    #expect(attached.material.map(\.filename) == ["client-email.txt", "pick.png", "repro.mov"])
    #expect(attached.material.map(\.isText) == [true, false, false])
    #expect(attached.material.map(\.isScreenshot) == [false, true, false])
    #expect(attached.material.map(\.isVideo) == [false, false, true])

    let reopened = try await harness.reopen().state()
    #expect(reopened.material.map(\.filename) == ["client-email.txt", "pick.png", "repro.mov"])
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

    /// The same Story reply, with the agent asking something back — what a Draft looks like
    /// when there is a conversation to read.
    static func asking(_ questions: String...) -> GenerateReply {
        GenerateReply(
            ticketType: .story,
            title: title,
            shortLabel: shortLabel,
            description: firstPassDescription,
            openQuestions: questions
        )
    }
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

    var projectJSONURL: URL { projectJSONURL("FAK") }

    func projectJSONURL(_ key: String) -> URL {
        root
            .appending(component: "projects")
            .appending(component: key)
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

    func reopen(
        settingsChanged: @escaping @Sendable (Settings?) async -> Void = { _ in }
    ) -> Session {
        Session(
            applicationSupport: root,
            model: model,
            jira: jira,
            transcriber: transcriber,
            secrets: secrets,
            settingsChanged: settingsChanged
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

    func generateTwoSiblingBatch() async throws -> (String, String) {
        _ = try await session.perform(.typeBrainDump(StoryReply.brainDump))
        let named = try await session.perform(
            .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
        )
        let firstId = try #require(named.batch?.siblings[0].id)
        let secondId = try #require(named.batch?.siblings[1].id)
        _ = try await session.perform(.generate)
        await model.replaceReply(
            GenerateReply(
                ticketType: .chore,
                title: ChoreReply.title,
                shortLabel: "export totals",
                description: ChoreReply.firstPassDescription,
                openQuestions: []
            )
        )
        _ = try await session.perform(.focusDraft(secondId))
        _ = try await session.perform(.generate)
        return (firstId, secondId)
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
    var textMaterialDisclosed: Bool?
}

// MARK: - #30 Session.State carries what a window needs

@Test func theConversationIsReadableFromStateWithBothSidesOfTheChat() async throws {
    let harness = Harness()
    await harness.model.replaceReply(StoryReply.asking("Which basket does the summary read?"))
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)

    #expect(
        generated.transcript == [
            TranscriptLine(role: .pm, text: StoryReply.brainDump),
            TranscriptLine(role: .agent, text: "Which basket does the summary read?"),
        ]
    )
}

@Test func restartRestoresTheInProgressDraftAndItsConversation() async throws {
    let harness = Harness()
    await harness.model.replaceReply(StoryReply.asking("Which basket does the summary read?"))
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    let draftId = try #require(generated.draft?.id)

    let restored = try await harness.reopen().state()

    #expect(restored.draft?.id == draftId)
    #expect(restored.draft?.title == StoryReply.title)
    #expect(
        restored.transcript == [
            TranscriptLine(role: .pm, text: StoryReply.brainDump),
            TranscriptLine(role: .agent, text: "Which basket does the summary read?"),
        ]
    )
}

@Test func aFailedBackgroundCatalogRefreshIsAFlagOnStateAndGenerateRunsOnTheLastGoodPull()
    async throws
{
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
    await harness.jira.setUnreachable(true)

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)

    // The stale snapshot is what Generate saw — a failed refresh warns, it never blocks.
    #expect(generated.catalog.rows.first?.title == "Scan tote before pick")
    #expect(generated.draft?.title == StoryReply.title)

    try await waitUntil { try await harness.session.state().catalogRefreshFailed }

    // The pull is still stale, so the next look starts another refresh. One that lands
    // clears the warning — it is a warning about the snapshot, not a scar.
    await harness.jira.setUnreachable(false)
    try await waitUntil { try await harness.session.state().catalogRefreshFailed == false }
}

@Test func theProviderDisclosureIsRaisedAtSetupAndAgainAtTheFirstTextMaterial() async throws {
    // The two moments §3.5 and story 14 name, and no third. Never in the Draft UI, which is why
    // it is one outstanding fact on state rather than anything that rests on the Draft.
    let harness = Harness(seedProject: false)
    await harness.jira.seedIssueTypes([
        JiraIssueType(name: "Epic", hierarchyLevel: 1, subtask: false),
        JiraIssueType(name: "Story", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Bug", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Chore", hierarchyLevel: 0, subtask: false),
    ])
    _ = try await harness.session.perform(firstLaunchCredentials)
    let proposed = try await harness.session.perform(.enterProjectKey("FAK"))
    #expect(proposed.textMaterialDisclosure == "Text Material is sent to the model provider.")

    // Confirming is reading it: the disclosure sits on the screen the PM confirms.
    let confirmed = try await harness.session.perform(
        .confirmProject(mapping: [.story: "Story", .bug: "Bug", .chore: "Chore"])
    )
    #expect(confirmed.proposedProject == nil)
    #expect(confirmed.textMaterialDisclosure == nil)

    let screenshot = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "pick.png", mimeType: "image/png", data: Data("png".utf8))
        )
    )
    #expect(screenshot.textMaterialDisclosure == nil)

    let attached = try await harness.session.perform(
        .attachMaterial(
            Material(
                filename: "client-email.txt",
                mimeType: "text/plain",
                data: Data("We need pickers to scan the bin.".utf8)
            )
        )
    )
    #expect(attached.textMaterialDisclosure == "Text Material is sent to the model provider.")

    let read = try await harness.session.perform(.acknowledgeTextMaterialDisclosure)
    #expect(read.textMaterialDisclosure == nil)

    let second = try await harness.session.perform(
        .attachMaterial(
            Material(
                filename: "support-ticket.txt",
                mimeType: "text/plain",
                data: Data("The picker grabbed from the wrong bin.".utf8)
            )
        )
    )
    #expect(second.textMaterialDisclosure == nil)

    // It is one warning per Project, not one per launch.
    let restarted = harness.reopen()
    let afterRestart = try await restarted.perform(
        .attachMaterial(
            Material(filename: "thread.txt", mimeType: "text/plain", data: Data("more".utf8))
        )
    )
    #expect(afterRestart.textMaterialDisclosure == nil)
}

@Test func aChatAnswerJoinsTheConversationAfterTheQuestionItAnswers() async throws {
    let harness = Harness()
    await harness.model.replaceReply(StoryReply.asking("Which basket does the summary read?"))
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)

    await harness.model.replaceReply(StoryReply.asking())
    _ = try await harness.session.perform(.typeBrainDump("The current basket, on load."))
    let answered = try await harness.session.perform(.send)

    #expect(
        answered.transcript == [
            TranscriptLine(role: .pm, text: StoryReply.brainDump),
            TranscriptLine(role: .agent, text: "Which basket does the summary read?"),
            TranscriptLine(role: .pm, text: "The current basket, on load."),
        ]
    )
}

@Test func theConversationFollowsTheFocusedBatchSibling() async throws {
    // §11: each Draft in a Batch is full — its own Ticket type, its own chat. A conversation
    // that stayed behind on a focus switch would show the wrong Draft's questions.
    let harness = Harness()
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .story,
            title: StoryReply.title,
            shortLabel: "scan bin",
            description: StoryReply.firstPassDescription,
            openQuestions: ["Which basket does the summary read?"]
        )
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let named = try await harness.session.perform(
        .nameBatch(name: "Checkout totals", shortLabels: ["scan bin", "export totals"])
    )
    let firstId = try #require(named.batch?.siblings[0].id)
    let secondId = try #require(named.batch?.siblings[1].id)
    _ = try await harness.session.perform(.generate)

    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .chore,
            title: ChoreReply.title,
            shortLabel: "export totals",
            description: ChoreReply.firstPassDescription,
            openQuestions: ["Which format does the export need?"]
        )
    )
    _ = try await harness.session.perform(.focusDraft(secondId))
    _ = try await harness.session.perform(.typeBrainDump("export the totals nightly"))
    let onChore = try await harness.session.perform(.generate)

    #expect(
        onChore.transcript == [
            TranscriptLine(role: .pm, text: "export the totals nightly"),
            TranscriptLine(role: .agent, text: "Which format does the export need?"),
        ]
    )

    let back = try await harness.session.perform(.focusDraft(firstId))
    #expect(
        back.transcript == [
            TranscriptLine(role: .pm, text: StoryReply.brainDump),
            TranscriptLine(role: .agent, text: "Which basket does the summary read?"),
        ]
    )
}

@Test func aRewriteStartsOnAnEmptyConversationNotTheCreateDraftsChat() async throws {
    // A rewrite is a new Draft bound to the key (§12). Carrying the create Draft's chat into it
    // would put questions about a different Ticket in the conversation, and persist them there.
    let harness = Harness()
    await harness.model.replaceReply(StoryReply.asking("Which basket does the summary read?"))
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let created = try await harness.session.perform(.generate)
    #expect(created.transcript.count == 2)

    await harness.jira.seed(
        epics: [],
        issues: [
            SeededIssue(
                key: "FAK-500",
                title: "Export totals nightly",
                jiraIssueType: "Story",
                labels: [],
                parentEpicKey: nil,
                status: "To Do",
                created: Date(timeIntervalSince1970: 1_700_000_200),
                body: "The nightly export drops the last row.",
                comments: []
            )
        ],
        componentNames: []
    )
    let rewriting = try await harness.session.perform(.pasteKey("FAK-500"))

    #expect(rewriting.rewrite != nil)
    #expect(rewriting.transcript.isEmpty)
}

@Test func aQuestionStillOpenAfterASendIsNotAskedTwiceInTheConversation() async throws {
    // The agent hands back its whole open-questions list every press, so a question the PM has
    // not answered comes back unchanged. The conversation must show it as one thing it asked,
    // not once per press.
    let harness = Harness()
    await harness.model.replaceReply(
        StoryReply.asking("Which basket does the summary read?", "Does it reach the payment step?")
    )
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)

    await harness.model.replaceReply(
        StoryReply.asking("Does it reach the payment step?", "Which format does the export need?")
    )
    _ = try await harness.session.perform(.typeBrainDump("The current basket, on load."))
    let answered = try await harness.session.perform(.send)

    #expect(
        answered.transcript == [
            TranscriptLine(role: .pm, text: StoryReply.brainDump),
            TranscriptLine(role: .agent, text: "Which basket does the summary read?"),
            TranscriptLine(role: .agent, text: "Does it reach the payment step?"),
            TranscriptLine(role: .pm, text: "The current basket, on load."),
            TranscriptLine(role: .agent, text: "Which format does the export need?"),
        ]
    )
}

// MARK: - #32 The Draft is editable, and Submit writes the Ticket

@Test func handEditsToTheDraftAreWhatSubmitWrites() async throws {
    let harness = Harness(ticketTypeMapping: [.story: "Task"])
    _ = try await harness.generateStory()

    let title = "As a warehouse picker I want the bin scan enforced so that I pick the right bin"
    let description = "On the **pick screen** the scan is required.\n\n---\n\n- Scan is enforced"
    _ = try await harness.session.perform(.editTitle(title))
    _ = try await harness.session.perform(.editShortLabel("enforce bin scan"))
    let edited = try await harness.session.perform(.editDescription(description))
    #expect(edited.draft?.title == title)
    #expect(edited.draft?.shortLabel == "enforce bin scan")
    #expect(edited.draft?.description == description)

    let state = try await harness.session.perform(.submit)
    let ticket = try #require(await harness.jira.created.first)
    #expect(ticket.title == title)
    #expect(ticket.descriptionWiki.contains("*pick screen*"))
    #expect(ticket.descriptionWiki.contains("* Scan is enforced"))
    #expect(state.catalog.rows.first?.shortLabel == "enforce bin scan")
}

@Test func handEditsSurviveARestart() async throws {
    let harness = Harness()
    _ = try await harness.generateStory()
    _ = try await harness.session.perform(.editTitle("As a picker I want it fixed so that I pick"))
    _ = try await harness.session.perform(.editShortLabel("bin scan"))
    _ = try await harness.session.perform(.editDescription("Edited body.\n\n---\n\n- Done"))

    let state = try await harness.reopen().state()
    #expect(state.draft?.title == "As a picker I want it fixed so that I pick")
    #expect(state.draft?.shortLabel == "bin scan")
    #expect(state.draft?.description == "Edited body.\n\n---\n\n- Done")
}

/// The section is composed from the agent's open questions, so an edit must never be able to put
/// a copy of it into the description — the next compose would sit a second one on top.
@Test func editingTheDescriptionNeverBakesInTheOpenQuestionsSection() async throws {
    let harness = Harness()
    _ = try await harness.generateStory(
        openQuestions: ["What should happen when the bin scan fails?"]
    )
    let generated = try #require(try await harness.session.state().draft)
    #expect(generated.descriptionWithOpenQuestions.contains(Draft.openQuestionsPreamble))
    #expect(!generated.description.contains(Draft.openQuestionsPreamble))

    let edited = try await harness.session.perform(
        .editDescription(generated.description + "\n\nOne more paragraph.")
    )
    let draft = try #require(edited.draft)
    #expect(!draft.description.contains(Draft.openQuestionsPreamble))
    #expect(
        draft.descriptionWithOpenQuestions.ranges(of: Draft.openQuestionsPreamble).count == 1
    )
}

@Test func anUploadQueueRefusesFurtherEdits() async throws {
    let harness = Harness()
    _ = try await harness.generateStory()
    let submitted = try await harness.session.perform(.submit)
    let draft = try #require(submitted.draft)

    let afterTitle = try await harness.session.perform(.editTitle("As a thief I want to edit"))
    let afterShortLabel = try await harness.session.perform(.editShortLabel("stolen"))
    let afterDescription = try await harness.session.perform(.editDescription("stolen body"))
    #expect(afterTitle.draft?.title == draft.title)
    #expect(afterShortLabel.draft?.shortLabel == draft.shortLabel)
    #expect(afterDescription.draft?.description == draft.description)
}

@Test func submitPutsTheKeyAndTheTicketLinkOnState() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(
        .saveCredentials(
            Settings(
                site: "example.atlassian.net",
                email: "pm@example.com",
                provider: "anthropic",
                modelId: "claude"
            ),
            jiraToken: "token",
            modelKey: "key"
        )
    )
    _ = try await harness.generateStory()
    #expect(try await harness.session.state().submitted == nil)

    let state = try await harness.session.perform(.submit)
    let submitted = try #require(state.submitted)
    #expect(submitted.key == TicketKey("FAK-1"))
    #expect(submitted.url == URL(string: "https://example.atlassian.net/browse/FAK-1"))
}

/// A rewrite Draft carries a key from the start and is still an editor, so the key alone cannot
/// be what says a Draft has been Submitted.
@Test func aRewriteDraftBoundToAKeyIsNotASubmittedTicket() async throws {
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
                comments: []
            )
        ],
        componentNames: []
    )
    let state = try await harness.session.perform(.pasteKey("FAK-231"))
    #expect(state.draft?.key == TicketKey("FAK-231"))
    #expect(state.submitted == nil)
}

@Test func aNewDraftAfterAFinishedQueueReturnsTheWindowToTheFrontDoor() async throws {
    let harness = Harness()
    _ = try await harness.generateStory()
    _ = try await harness.session.perform(
        .attachMaterial(Material(filename: "shot.png", mimeType: "image/png", data: Data([0x1])))
    )
    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.submitted?.key == TicketKey("FAK-1"))
    #expect(submitted.failedUploads.isEmpty)

    let fresh = try await harness.session.perform(.newDraft)
    #expect(fresh.draft == nil)
    #expect(fresh.submitted == nil)
    #expect(fresh.field == "")
    #expect(fresh.material.isEmpty)
    #expect(fresh.transcript.isEmpty)
    #expect(try await harness.reopen().state().draft == nil)
}

@Test func aNewDraftIsRefusedWhileThereIsStillSomethingOnlyFakthisHas() async throws {
    let harness = Harness()
    _ = try await harness.generateStory()

    let unsubmitted = try await harness.session.perform(.newDraft)
    #expect(unsubmitted.draft?.title == StoryReply.title)

    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "clip.mov", mimeType: "video/quicktime", data: Data([0x1]))
        )
    )
    await harness.jira.setFailUploads(true)
    let queued = try await harness.session.perform(.submit)
    #expect(queued.failedUploads == ["clip.mov"])

    let refused = try await harness.session.perform(.newDraft)
    #expect(refused.draft?.key == TicketKey("FAK-1"))
    #expect(refused.failedUploads == ["clip.mov"])

    await harness.jira.setFailUploads(false)
    _ = try await harness.session.perform(.retryUploads)
    #expect(try await harness.session.perform(.newDraft).draft == nil)
}

/// The only queue that survives a restart is one still holding a file, because a finished one
/// deletes its folder. Reopened, it is still the Ticket and still not an editor.
@Test func aRestartedUploadQueueIsStillTheTicketAndStillRefusesEdits() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(
        .saveCredentials(
            Settings(
                site: "example.atlassian.net",
                email: "pm@example.com",
                provider: "anthropic",
                modelId: "claude"
            ),
            jiraToken: "token",
            modelKey: "key"
        )
    )
    _ = try await harness.generateStory()
    _ = try await harness.session.perform(
        .attachMaterial(
            Material(filename: "clip.mov", mimeType: "video/quicktime", data: Data([0x1]))
        )
    )
    await harness.jira.setFailUploads(true)
    let queued = try await harness.session.perform(.submit)
    #expect(queued.failedUploads == ["clip.mov"])

    let restarted = harness.reopen()
    let reopened = try await restarted.state()
    #expect(reopened.submitted?.key == TicketKey("FAK-1"))
    #expect(reopened.submitted?.url == URL(string: "https://example.atlassian.net/browse/FAK-1"))
    #expect(reopened.failedUploads == ["clip.mov"])

    let edited = try await restarted.perform(.editTitle("As a thief I want to edit after Submit"))
    #expect(edited.draft?.title == StoryReply.title)
}

/// A file Jira refused at attach time is kept with the Draft and never uploaded, so the window
/// has to be able to tell it apart from one that reached the Ticket.
@Test func materialJiraWillNotTakeIsMarkedBlockedOnState() async throws {
    let harness = Harness()
    await harness.jira.setAttachmentPolicy(AttachmentPolicy(enabled: true, uploadLimit: 4))
    _ = try await harness.generateStory()
    let state = try await harness.session.perform(
        .attachMaterial(
            Material(
                filename: "huge.mov",
                mimeType: "video/quicktime",
                data: Data(repeating: 0x1, count: 64)
            )
        )
    )
    let attached = try #require(state.material.first)
    #expect(attached.filename == "huge.mov")
    #expect(attached.blockedFromUpload)

    let submitted = try await harness.session.perform(.submit)
    #expect(submitted.submitted?.key == TicketKey("FAK-1"))
    #expect(await harness.jira.uploaded.isEmpty)
    #expect(submitted.failedUploads.isEmpty)
}

// MARK: - #33 The conversation column, collapsible

@Test func aSentAnswerLeavesTheComposerSoItIsNotOfferedTwice() async throws {
    // The composer is `Session`'s field, and the press spends it. A copy left behind would sit
    // in the composer under the answer it already produced, and a second Send would record the
    // same thing the conversation is already showing.
    let harness = Harness()
    await harness.model.replaceReply(StoryReply.asking("Which basket does the summary read?"))
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.field.isEmpty)

    await harness.model.replaceReply(StoryReply.asking())
    _ = try await harness.session.perform(.typeBrainDump("The current basket, on load."))
    let answered = try await harness.session.perform(.send)

    #expect(answered.field.isEmpty)
    #expect(
        answered.transcript == [
            TranscriptLine(role: .pm, text: StoryReply.brainDump),
            TranscriptLine(role: .agent, text: "Which basket does the summary read?"),
            TranscriptLine(role: .pm, text: "The current basket, on load."),
        ]
    )
}

@Test func sendOnAnEmptyComposerSaysNothingToTheAgent() async throws {
    let harness = Harness()
    let generated = try await harness.generateStory(
        openQuestions: ["Which basket does the summary read?"]
    )
    let requestsAfterGenerate = await harness.model.completeRequests.count

    let pressed = try await harness.session.perform(.send)

    #expect(await harness.model.completeRequests.count == requestsAfterGenerate)
    #expect(pressed.transcript == generated.transcript)
    #expect(pressed.draft == generated.draft)
}

@Test func changingTicketTypeMidChatKeepsTheConversation() async throws {
    // §7.4: a reshape against the new template keeps Material and the answers already given.
    // The conversation is where those answers are read, so it survives the reshape.
    let harness = Harness()
    await harness.model.replaceReply(StoryReply.asking("Which basket does the summary read?"))
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)

    await harness.model.replaceReply(StoryReply.asking())
    _ = try await harness.session.perform(.typeBrainDump("The current basket, on load."))
    _ = try await harness.session.perform(.send)

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
    #expect(
        reshaped.transcript == [
            TranscriptLine(role: .pm, text: StoryReply.brainDump),
            TranscriptLine(role: .agent, text: "Which basket does the summary read?"),
            TranscriptLine(role: .pm, text: "The current basket, on load."),
        ]
    )
}

@Test func aHalfTypedAnswerIsNotSaidByChangingTheTicketType() async throws {
    // A reshape is not the PM saying something. An answer still being typed has not been Sent,
    // so it neither joins the conversation nor leaves the composer.
    let harness = Harness()
    await harness.model.replaceReply(StoryReply.asking("Which basket does the summary read?"))
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)

    _ = try await harness.session.perform(.typeBrainDump("the current basket, on lo"))
    await harness.model.replaceReply(
        GenerateReply(
            ticketType: .bug,
            title: BugReply.title,
            shortLabel: BugReply.shortLabel,
            description: BugReply.firstPassDescription,
            openQuestions: ["Which browsers has this been seen on?"]
        )
    )
    let reshaped = try await harness.session.perform(.changeTicketType(.bug))

    #expect(reshaped.field == "the current basket, on lo")
    #expect(
        reshaped.transcript == [
            TranscriptLine(role: .pm, text: StoryReply.brainDump),
            TranscriptLine(role: .agent, text: "Which basket does the summary read?"),
            TranscriptLine(role: .agent, text: "Which browsers has this been seen on?"),
        ]
    )
}

@Test func workingOnADuplicateLocalDraftShowsThatDraftsConversation() async throws {
    // The conversation on screen is always the focused Draft's. Landing on the Draft the
    // duplicate matched while the abandoned one's chat stayed up would put questions about a
    // different Ticket in the column.
    let harness = Harness()
    await harness.model.replaceReply(StoryReply.asking("Which basket does the summary read?"))
    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    let generated = try await harness.session.perform(.generate)
    #expect(generated.transcript.count == 2)

    let otherId = "other-draft"
    try harness.writeDraft(
        id: otherId,
        ticketType: .story,
        title: "As a picker I want to scan a bin so that I pick from the right location",
        shortLabel: StoryReply.shortLabel,
        description: "A sibling Draft about scanning a bin."
    )
    let rematched = try await harness.session.perform(.generate)
    #expect(rematched.duplicateInterrupt?.draftId == otherId)

    let focused = try await harness.session.perform(.workOnDuplicate)

    #expect(focused.draft?.id == otherId)
    #expect(focused.transcript.isEmpty)
}

// MARK: - #35 Setup, the Project list, and Project terms

@Test func theProjectListIsEveryLocalProjectAndOpeningOneOpensThatProject() async throws {
    let harness = Harness()
    try harness.writeProject(
        Project(key: "PROD", ticketTypeMapping: [.story: "Story"], terms: ["pallet"])
    )
    let session = harness.reopen()

    let listed = try await session.state()
    #expect(listed.projects == ["FAK", "PROD"])
    #expect(listed.project?.key == "FAK")

    let opened = try await session.perform(.openProject("PROD"))
    #expect(opened.project?.key == "PROD")
    #expect(opened.project?.terms == ["pallet"])
    #expect(opened.projects == ["FAK", "PROD"])
}

@Test func openingAProjectLeavesTheOtherProjectsDraftAndCatalogBehind() async throws {
    let harness = Harness()
    try harness.writeCatalog(
        pulledAt: Date(),
        epics: [CatalogEpic(key: TicketKey("FAK-100"), name: "Picking", status: "To Do")],
        rows: [],
        componentNames: []
    )
    let generated = try await harness.generateStory()
    #expect(generated.draft?.title == StoryReply.title)

    try harness.writeProject(
        Project(key: "PROD", ticketTypeMapping: [.story: "Story"], terms: [])
    )
    let session = harness.reopen()
    #expect(try await session.state().draft?.title == StoryReply.title)

    let switched = try await session.perform(.openProject("PROD"))
    #expect(switched.draft == nil)
    #expect(switched.catalog.epics.isEmpty)
    #expect(switched.field.isEmpty)

    let back = try await session.perform(.openProject("FAK"))
    #expect(back.draft?.title == StoryReply.title)
    #expect(back.catalog.epics.count == 1)
}

@Test func theProjectTheListOpenedIsWhereTheNextLaunchLands() async throws {
    let harness = Harness()
    try harness.writeProject(
        Project(key: "PROD", ticketTypeMapping: [.story: "Story"], terms: [])
    )
    let session = harness.reopen()
    _ = try await session.perform(.openProject("PROD"))

    #expect(try await harness.reopen().state().project?.key == "PROD")
}

@Test func addingASecondProjectOpensItAndTakesItsOwnFirstCatalogPull() async throws {
    let harness = Harness(seedProject: false)
    await harness.jira.seedIssueTypes([
        JiraIssueType(name: "Story", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Bug", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Chore", hierarchyLevel: 0, subtask: false),
    ])
    await harness.jira.seed(
        epics: [SeededEpic(key: "FAK-100", name: "Picking", status: "To Do", description: "")],
        issues: [],
        componentNames: []
    )
    _ = try await harness.session.perform(firstLaunchCredentials)
    let mapping: [TicketType: String] = [.story: "Story", .bug: "Bug", .chore: "Chore"]
    _ = try await harness.session.perform(.enterProjectKey("FAK"))
    let first = try await harness.session.perform(.confirmProject(mapping: mapping))
    #expect(first.project?.key == "FAK")
    #expect(first.catalog.epics.count == 1)

    _ = try await harness.session.perform(.enterProjectKey("PROD"))
    let second = try await harness.session.perform(.confirmProject(mapping: mapping))

    #expect(second.project?.key == "PROD")
    #expect(second.projects == ["FAK", "PROD"])
    #expect(await harness.jira.catalogPulls == ["FAK", "PROD"])
    #expect(second.catalog.epics.count == 1)
}

@Test func anEmptyCatalogAtProjectCreationOpensTheProjectAndGenerateStillRuns() async throws {
    let harness = Harness(seedProject: false)
    await harness.jira.seedIssueTypes([
        JiraIssueType(name: "Task", hierarchyLevel: 0, subtask: false)
    ])
    _ = try await harness.session.perform(firstLaunchCredentials)
    let proposed = try await harness.session.perform(.enterProjectKey("FAK"))
    let mapping = try #require(proposed.proposedProject?.mapping)
    let confirmed = try await harness.session.perform(.confirmProject(mapping: mapping))

    #expect(confirmed.project?.key == "FAK")
    #expect(confirmed.catalog.rows.isEmpty)
    #expect(await harness.jira.catalogPulls == ["FAK"])

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    #expect(try await harness.session.perform(.generate).draft?.title == StoryReply.title)
}

@Test func dismissingAProposedProjectAddsNothing() async throws {
    let harness = Harness(seedProject: false)
    await harness.jira.seedIssueTypes([
        JiraIssueType(name: "Task", hierarchyLevel: 0, subtask: false)
    ])
    _ = try await harness.session.perform(firstLaunchCredentials)
    _ = try await harness.session.perform(.enterProjectKey("FAK"))

    let dismissed = try await harness.session.perform(.dismissProposedProject)
    #expect(dismissed.proposedProject == nil)
    #expect(dismissed.projects.isEmpty)
    #expect(dismissed.project == nil)
    #expect(dismissed.textMaterialDisclosure == nil)
}

@Test func theSiteIsKeptAsAHostnameHoweverThePMPastedIt() async throws {
    let harness = Harness(seedProject: false)
    let saved = try await harness.session.perform(
        .saveCredentials(
            Settings(
                site: "  https://your-team.atlassian.net/jira/software/projects/FAK/boards/1  ",
                email: "pm@company.com",
                provider: "openai",
                modelId: "gpt-5.6-luna"
            ),
            jiraToken: "jira-secret",
            modelKey: "model-secret"
        )
    )

    #expect(saved.settings?.site == "your-team.atlassian.net")
    #expect(try await harness.reopen().state().settings?.site == "your-team.atlassian.net")
}

/// The regression the two network adapters are built for: they read the settings at the call,
/// so a launch that hands them over late makes its own first call without a site and marks the
/// Catalog refresh failed for no reason.
@Test func aLaunchHandsOverTheSettingsBeforeItCanSpendThem() async throws {
    let harness = Harness()
    _ = try await harness.session.perform(firstLaunchCredentials)
    try harness.writeCatalog(
        pulledAt: Date().addingTimeInterval(-3601),
        epics: [],
        rows: [],
        componentNames: []
    )

    let jira = harness.jira
    let pullsBeforeHandover = JiraPullsAtHandover()
    let relaunched = harness.reopen(settingsChanged: { _ in
        await pullsBeforeHandover.record(await jira.catalogPulls.count)
    })

    _ = try await relaunched.state()
    try await waitUntil { await jira.catalogPulls.count == 1 }

    #expect(await pullsBeforeHandover.counts == [0])
}

/// How much Jira had already been asked for each time the settings were handed over.
private actor JiraPullsAtHandover {
    private(set) var counts: [Int] = []

    func record(_ pulls: Int) {
        counts.append(pulls)
    }
}

@Test func aProjectKeyJiraWillNotAnswerForProposesNothingAndLosesNothing() async throws {
    for refusal in [Refusal.unreachable, .noSuchProject] {
        let harness = Harness(seedProject: false)
        if refusal == .unreachable {
            await harness.jira.seedIssueTypes([
                JiraIssueType(name: "Task", hierarchyLevel: 0, subtask: false)
            ])
            await harness.jira.setUnreachable(true)
        }
        _ = try await harness.session.perform(firstLaunchCredentials)

        let refused = try await harness.session.perform(.enterProjectKey("NOPE"))
        #expect(refused.proposedProject == nil)
        #expect(refused.projects.isEmpty)
        #expect(refused.project == nil)
        #expect(refused.settings != nil)
    }
}

private enum Refusal {
    case unreachable
    case noSuchProject
}

@Test func projectTermsStartEmptyAndAreEditedOnTheProject() async throws {
    let harness = Harness()
    #expect(try await harness.session.state().project?.terms == [])

    let edited = try await harness.session.perform(
        .editProjectTerms(["bin", "   ", "  pick screen  "])
    )
    #expect(edited.project?.terms == ["bin", "pick screen"])

    let onDisk = try JSONDecoder().decode(
        DiskProject.self,
        from: Data(contentsOf: harness.projectJSONURL)
    )
    #expect(onDisk.terms == ["bin", "pick screen"])
    #expect(try await harness.reopen().state().project?.terms == ["bin", "pick screen"])
}

@Test func editedProjectTermsReachGenerateAsContextAndTheTranscriberAsItsBoostList()
    async throws
{
    let harness = Harness()
    _ = try await harness.session.perform(.editProjectTerms(["bin", "pick screen"]))

    await harness.transcriber.enqueueTake("scan the bin")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    #expect(await harness.transcriber.boostLists == [["bin", "pick screen"]])

    _ = try await harness.session.perform(.typeBrainDump(StoryReply.brainDump))
    _ = try await harness.session.perform(.generate)
    let system = try #require(await harness.model.completeRequests.first?.system)
    #expect(system.contains("Project terms:\nbin\npick screen"))
}

@Test func clearingProjectTermsTurnsBiasingOffRatherThanBiasingOnNothing() async throws {
    let harness = Harness(terms: ["bin"])
    _ = try await harness.session.perform(.editProjectTerms([]))
    #expect(try await harness.session.state().project?.terms == [])

    await harness.transcriber.enqueueTake("scan the bin")
    _ = try await harness.session.perform(.startListening)
    _ = try await harness.session.perform(.stopListening)
    #expect(await harness.transcriber.boostLists == [[]])
}
