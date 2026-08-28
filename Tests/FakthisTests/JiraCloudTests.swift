import Foundation
import Testing
import Fakthis

@Test func jiraCloudCreatePostsWikiMarkupToV2IssueWithoutNotifyUsers() async throws {
    let http = ScriptedHTTP()
    await http.queue(status: 201, json: #"{"id":"10001","key":"FAK-1"}"#)
    let jira = jiraCloud(http)

    let key = try await jira.createTicket(
        projectKey: "FAK",
        title: "As a picker I want a bin scan so that picks are accurate",
        descriptionWiki: "On the *pick screen* a picker scans the *bin*.\n----\n* items are taken",
        jiraIssueType: "Story",
        parentKey: nil
    )

    #expect(key == TicketKey("FAK-1"))
    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://faktion.atlassian.net/rest/api/2/issue")
    #expect(request.url?.query == nil)
    #expect(
        request.value(forHTTPHeaderField: "Authorization") == "Basic "
            + Data("pm@faktion.com:secret-token".utf8).base64EncodedString()
    )
    let fields = try issueFields(request)
    #expect(fields["summary"] as? String == "As a picker I want a bin scan so that picks are accurate")
    #expect((fields["project"] as? [String: Any])?["key"] as? String == "FAK")
    #expect((fields["issuetype"] as? [String: Any])?["name"] as? String == "Story")
    #expect(fields["parent"] == nil)
    let description = try #require(fields["description"] as? String)
    #expect(description.contains("*pick screen*"))
    #expect(description.contains("*bin*"))
    #expect(!description.contains("**"))
    #expect(description.contains("----"))
}

@Test func jiraCloudCreateIncludesEpicAsFieldsParent() async throws {
    let http = ScriptedHTTP()
    await http.queue(status: 201, json: #"{"key":"FAK-1"}"#)
    let jira = jiraCloud(http)

    _ = try await jira.createTicket(
        projectKey: "FAK",
        title: "Scan tote before pick",
        descriptionWiki: "The tote scan is required.",
        jiraIssueType: "Story",
        parentKey: TicketKey("FAK-100")
    )

    let fields = try issueFields(try #require(await http.requests.last))
    #expect((fields["parent"] as? [String: Any])?["key"] as? String == "FAK-100")
}

@Test func jiraCloudUpdateWritesTitleDescriptionAndAddsCompletenessMarkerWithoutNotifyUsers()
    async throws
{
    let http = ScriptedHTTP()
    await http.queue(status: 204, json: "")
    let jira = jiraCloud(http)

    try await jira.updateTicket(
        key: TicketKey("FAK-231"),
        title: "As a picker I want a bin scan so that picks are accurate",
        descriptionWiki: "On the *pick screen* a picker scans the *bin*.",
        completenessMarker: .apply
    )

    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "PUT")
    #expect(
        request.url?.absoluteString == "https://faktion.atlassian.net/rest/api/2/issue/FAK-231"
    )
    #expect(request.url?.query == nil)
    #expect(request.url?.query?.contains("notifyUsers") != true)
    let body = try #require(request.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let fields = try #require(json["fields"] as? [String: Any])
    #expect(Set(fields.keys) == ["summary", "description"])
    #expect(
        fields["summary"] as? String
            == "As a picker I want a bin scan so that picks are accurate"
    )
    #expect(fields["description"] as? String == "On the *pick screen* a picker scans the *bin*.")
    let update = try #require(json["update"] as? [String: Any])
    #expect(Set(update.keys) == ["labels"])
    let labels = try #require(update["labels"] as? [[String: String]])
    #expect(labels == [["add": "fakthis-open-questions"]])
}

@Test func jiraCloudUpdateRemovesCompletenessMarkerWhenQuestionsAreAnswered() async throws {
    let http = ScriptedHTTP()
    await http.queue(status: 204, json: "")
    let jira = jiraCloud(http)

    try await jira.updateTicket(
        key: TicketKey("FAK-231"),
        title: "Scan tote before pick",
        descriptionWiki: "The tote scan is required.",
        completenessMarker: .clear
    )

    let body = try #require(await http.requests.last?.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let labels = try #require((json["update"] as? [String: Any])?["labels"] as? [[String: String]])
    #expect(labels == [["remove": "fakthis-open-questions"]])
}

@Test func jiraCloudQueriesAttachmentMetaAndUploadsAfterTheIssueExists() async throws {
    let http = ScriptedHTTP()
    await http.queue(status: 200, json: #"{"enabled":true,"uploadLimit":10485760}"#)
    await http.queue(status: 200, json: "[]")
    let jira = jiraCloud(http)

    let policy = try await jira.attachmentPolicy()
    #expect(policy.enabled)
    #expect(policy.uploadLimit == 10_485_760)

    try await jira.uploadAttachment(
        key: TicketKey("FAK-1"),
        filename: "pick.png",
        mimeType: "image/png",
        data: Data("png-bytes".utf8)
    )

    let meta = try #require(await http.requests.first)
    #expect(meta.httpMethod == "GET")
    #expect(
        meta.url?.absoluteString
            == "https://faktion.atlassian.net/rest/api/3/attachment/meta"
    )

    let upload = try #require(await http.requests.last)
    #expect(upload.httpMethod == "POST")
    #expect(
        upload.url?.absoluteString
            == "https://faktion.atlassian.net/rest/api/2/issue/FAK-1/attachments"
    )
    #expect(upload.value(forHTTPHeaderField: "X-Atlassian-Token") == "no-check")
    let contentType = try #require(upload.value(forHTTPHeaderField: "Content-Type"))
    #expect(contentType.hasPrefix("multipart/form-data; boundary="))
    let body = try #require(upload.httpBody.flatMap { String(data: $0, encoding: .utf8) })
    #expect(body.contains("filename=\"pick.png\""))
    #expect(body.contains("png-bytes"))
}

@Test func jiraCloudReadsCreatemetaAndMapsTicketTypesByNameElseDefaultStandardType() async throws {
    let http = ScriptedHTTP()
    await http.queue(
        status: 200,
        json: """
            {"issueTypes":[
              {"name":"Epic","subtask":false,"hierarchyLevel":1},
              {"name":"Task","subtask":false,"hierarchyLevel":0},
              {"name":"Story","subtask":false,"hierarchyLevel":0},
              {"name":"Bug","subtask":false,"hierarchyLevel":0},
              {"name":"Sub-task","subtask":true,"hierarchyLevel":-1}
            ]}
            """
    )
    let jira = jiraCloud(http)

    let types = try await jira.fetchIssueTypes(projectKey: "FAK")
    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "GET")
    #expect(
        request.url?.absoluteString
            == "https://faktion.atlassian.net/rest/api/3/issue/createmeta/FAK/issuetypes"
    )
    #expect(types.contains { $0.name == "Story" && !$0.subtask && $0.hierarchyLevel == 0 })
    #expect(types.contains { $0.name == "Epic" })

    let mapping = TicketType.mapping(from: types)
    #expect(mapping[.story] == "Story")
    #expect(mapping[.bug] == "Bug")
    #expect(mapping[.chore] == "Task")
}

@Test func jiraCloudOrdersRewriteCommentsByParsedInstantNewestFirst() async throws {
    let http = ScriptedHTTP()
    await http.queue(
        status: 200,
        json: """
            {"key":"FAK-231","fields":{
              "summary":"Scan tote before pick",
              "description":"Live body as Material",
              "issuetype":{"name":"Story"},
              "updated":"2024-06-01T12:00:00.000+0000",
              "comment":{"comments":[
                {"body":"lexically later but older","created":"2024-05-02T00:00:00.000+0200"},
                {"body":"actually newest","created":"2024-05-01T23:00:00.000+0000"}
              ]}
            }}
            """
    )
    let ticket = try await jiraCloud(http).fetchRewriteTarget(key: TicketKey("FAK-231"))
    #expect(ticket.comments.first == "actually newest")
}

@Test func jiraCloudFetchesARewriteTargetByKey() async throws {
    let http = ScriptedHTTP()
    await http.queue(
        status: 200,
        json: """
            {"key":"FAK-231","fields":{
              "summary":"Scan tote before pick",
              "description":"Live body as Material",
              "issuetype":{"name":"Story"},
              "updated":"2024-06-01T12:00:00.000+0000",
              "comment":{"comments":[
                {"body":"older comment","created":"2024-05-01T12:00:00.000+0000"},
                {"body":"newest comment","created":"2024-06-01T12:00:00.000+0000"}
              ]}
            }}
            """
    )
    let jira = jiraCloud(http)

    let ticket = try await jira.fetchRewriteTarget(key: TicketKey("FAK-231"))
    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/rest/api/2/issue/FAK-231")
    #expect(ticket.key == TicketKey("FAK-231"))
    #expect(ticket.title == "Scan tote before pick")
    #expect(ticket.description == "Live body as Material")
    #expect(ticket.jiraIssueType == "Story")
    #expect(ticket.comments.first == "newest comment")
    #expect(ticket.comments.count == 2)
}

@Test func jiraCloudWritesBatchBlocksAsAnIssueLink() async throws {
    let http = ScriptedHTTP()
    await http.queue(status: 201, json: "")
    let jira = jiraCloud(http)

    try await jira.createBlocksLink(blocker: TicketKey("FAK-1"), blocked: TicketKey("FAK-2"))

    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://faktion.atlassian.net/rest/api/2/issueLink")
    let body = try #require(request.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect((json["type"] as? [String: Any])?["name"] as? String == "Blocks")
    #expect((json["outwardIssue"] as? [String: Any])?["key"] as? String == "FAK-1")
    #expect((json["inwardIssue"] as? [String: Any])?["key"] as? String == "FAK-2")
}

@Test func jiraCloudPullsCatalogByKeysThenBulkfetchAndOmitsBodiesAndComments() async throws {
    let http = ScriptedHTTP()
    await http.queue(status: 200, json: #"{"issues":[{"key":"FAK-100"}]}"#)
    await http.queue(status: 200, json: #"{"issues":[{"key":"FAK-231"}]}"#)
    await http.queue(
        status: 200,
        json: """
            {"issues":[{"key":"FAK-100","fields":{
              "summary":"Warehouse picking",
              "status":{"name":"In Progress"},
              "description":"Epic Scope must not enter the Catalog"
            }}]}
            """
    )
    await http.queue(
        status: 200,
        json: """
            {"issues":[{"key":"FAK-231","fields":{
              "summary":"Scan tote before pick",
              "issuetype":{"name":"Story"},
              "labels":["picking"],
              "parent":{"key":"FAK-100"},
              "status":{"name":"To Do"},
              "created":"2024-06-01T12:00:00.000+0000",
              "description":"Issue body is Scope",
              "comment":{"comments":[{"body":"a comment"}]}
            }}]}
            """
    )
    await http.queue(status: 200, json: #"[{"name":"Pick App"}]"#)
    let jira = jiraCloud(http)

    let catalog = try await jira.pullCatalog(projectKey: "FAK")
    let requests = await http.requests
    #expect(requests.count == 5)
    #expect(requests[0].httpMethod == "GET")
    #expect(requests[0].url?.path == "/rest/api/3/search/jql")
    #expect(requests[0].url?.query?.contains("fields=key") == true)
    #expect(
        requests[0].url?.query?.contains("issuetype%20%3D%20Epic") == true
            || requests[0].url?.query?.contains("issuetype = Epic") == true
    )
    #expect(requests[1].url?.query?.contains("maxResults=300") == true)
    #expect(requests[2].httpMethod == "POST")
    #expect(requests[2].url?.path == "/rest/api/3/issue/bulkfetch")
    #expect(requests[3].url?.path == "/rest/api/3/issue/bulkfetch")
    #expect(requests[4].url?.path == "/rest/api/3/project/FAK/components")
    let epicBody = try #require(requests[2].httpBody)
    let epicFetch = try #require(try JSONSerialization.jsonObject(with: epicBody) as? [String: Any])
    #expect(epicFetch["issueIdsOrKeys"] as? [String] == ["FAK-100"])
    #expect(catalog.epics == [
        CatalogEpic(key: TicketKey("FAK-100"), name: "Warehouse picking", status: "In Progress")
    ])
    let row = try #require(catalog.rows.first)
    #expect(row.title == "Scan tote before pick")
    #expect(row.labels == ["picking"])
    #expect(row.parentEpicKey == TicketKey("FAK-100"))
    #expect(catalog.componentNames == ["Pick App"])
    #expect(row.title != "Issue body is Scope")
}

@Test func jiraCloudSkipsBulkfetchWhenTheCatalogSearchReturnsNoKeys() async throws {
    let http = ScriptedHTTP()
    await http.queue(status: 200, json: #"{"issues":[]}"#)
    await http.queue(status: 200, json: #"{"issues":[]}"#)
    await http.queue(status: 200, json: "[]")
    let jira = jiraCloud(http)

    let catalog = try await jira.pullCatalog(projectKey: "FAK")
    let paths = await http.requests.compactMap(\.url?.path)
    #expect(paths == [
        "/rest/api/3/search/jql",
        "/rest/api/3/search/jql",
        "/rest/api/3/project/FAK/components",
    ])
    #expect(catalog.epics.isEmpty)
    #expect(catalog.rows.isEmpty)
}

@Test func jiraCloudBulkFetchesCatalogInPagesOfOneHundred() async throws {
    let http = ScriptedHTTP()
    let epicKeys = (1...101).map { "FAK-\($0)" }
    let searchIssues = epicKeys.map { "{\"key\":\"\($0)\"}" }.joined(separator: ",")
    await http.queue(status: 200, json: "{\"issues\":[\(searchIssues)]}")
    await http.queue(status: 200, json: #"{"issues":[]}"#)
    func bulkBody(_ keys: ArraySlice<String>) -> String {
        let issues = keys.map {
            "{\"key\":\"\($0)\",\"fields\":{\"summary\":\"\($0)\",\"status\":{\"name\":\"Open\"}}}"
        }.joined(separator: ",")
        return "{\"issues\":[\(issues)]}"
    }
    await http.queue(status: 200, json: bulkBody(epicKeys.prefix(100)))
    await http.queue(status: 200, json: bulkBody(epicKeys.suffix(1)))
    await http.queue(status: 200, json: "[]")

    let catalog = try await jiraCloud(http).pullCatalog(projectKey: "FAK")
    let requests = await http.requests
    #expect(catalog.epics.count == 101)
    #expect(requests.filter { $0.url?.path == "/rest/api/3/issue/bulkfetch" }.count == 2)
    let firstBody = try #require(requests[2].httpBody)
    let firstFetch = try #require(try JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
    #expect((firstFetch["issueIdsOrKeys"] as? [String])?.count == 100)
    let secondBody = try #require(requests[3].httpBody)
    let secondFetch = try #require(
        try JSONSerialization.jsonObject(with: secondBody) as? [String: Any]
    )
    #expect(secondFetch["issueIdsOrKeys"] as? [String] == ["FAK-101"])
}

@Test func jiraCloudPagesCatalogSearchUntilTheCursorEnds() async throws {
    let http = ScriptedHTTP()
    await http.queue(
        status: 200,
        json: #"{"issues":[{"key":"FAK-100"}],"nextPageToken":"page-2"}"#
    )
    await http.queue(status: 200, json: #"{"issues":[{"key":"FAK-101"}]}"#)
    await http.queue(status: 200, json: #"{"issues":[]}"#)
    await http.queue(
        status: 200,
        json: """
            {"issues":[
              {"key":"FAK-100","fields":{"summary":"Warehouse picking","status":{"name":"Open"}}},
              {"key":"FAK-101","fields":{"summary":"Returns","status":{"name":"Open"}}}
            ]}
            """
    )
    await http.queue(status: 200, json: "[]")
    let jira = jiraCloud(http)

    let catalog = try await jira.pullCatalog(projectKey: "FAK")
    let requests = await http.requests
    #expect(requests[1].url?.query?.contains("nextPageToken=page-2") == true)
    #expect(catalog.epics.map(\.key) == [TicketKey("FAK-100"), TicketKey("FAK-101")])
}

@Test func jiraCloudMapsTransportFailureToUnreachable() async throws {
    let jira = JiraCloud(
        host: "faktion.atlassian.net",
        email: "pm@faktion.com",
        apiToken: "secret-token",
        send: { _ in throw URLError(.cannotFindHost) }
    )
    await #expect(throws: JiraUnreachable.self) {
        try await jira.fetchIssueTypes(projectKey: "FAK")
    }
}

actor ScriptedHTTP {
    private var queued: [(Data, Int)] = []
    private(set) var requests: [URLRequest] = []

    func queue(status: Int, json: String) {
        queued.append((Data(json.utf8), status))
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !queued.isEmpty else {
            throw URLError(.cannotFindHost)
        }
        let (data, status) = queued.removeFirst()
        let url = request.url ?? URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private func jiraCloud(_ http: ScriptedHTTP) -> JiraCloud {
    JiraCloud(
        host: "faktion.atlassian.net",
        email: "pm@faktion.com",
        apiToken: "secret-token",
        send: { try await http.send($0) }
    )
}

private func issueFields(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try #require(json["fields"] as? [String: Any])
}
