import Fakthis

struct ModelDraftRequest: Equatable, Sendable {
    var brainDump: String
    var catalog: Catalog
    var projectTerms: [String]
}

actor ScriptedModel: Model {
    var reply: GenerateReply
    let definitionOfDone: [String]
    private(set) var draftRequests: [ModelDraftRequest] = []
    private(set) var definitionOfDoneRequests: [String] = []

    init(reply: GenerateReply, definitionOfDone: [String]) {
        self.reply = reply
        self.definitionOfDone = definitionOfDone
    }

    func replaceReply(_ reply: GenerateReply) {
        self.reply = reply
    }

    func generateDraft(brainDump: String, catalog: Catalog, projectTerms: [String]) async throws
        -> GenerateReply
    {
        draftRequests.append(
            ModelDraftRequest(brainDump: brainDump, catalog: catalog, projectTerms: projectTerms)
        )
        return reply
    }

    func generateDefinitionOfDone(description: String) async throws -> [String] {
        definitionOfDoneRequests.append(description)
        return definitionOfDone
    }
}

struct CreatedTicket: Equatable, Sendable {
    var title: String
    var descriptionWiki: String
    var issueType: String
}

actor FakeJira: Jira {
    var unreachable = false
    var nextKey = TicketKey("FAK-1")
    private(set) var created: [CreatedTicket] = []

    func createTicket(title: String, descriptionWiki: String, issueType: String) async throws
        -> TicketKey
    {
        if unreachable { throw JiraUnreachable() }
        created.append(
            CreatedTicket(title: title, descriptionWiki: descriptionWiki, issueType: issueType)
        )
        return nextKey
    }

    func setUnreachable(_ value: Bool) {
        unreachable = value
    }
}
