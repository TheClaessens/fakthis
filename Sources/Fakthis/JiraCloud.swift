import Foundation

public actor JiraCloud: Jira {
    private let host: String
    private let email: String
    private let apiToken: @Sendable () async throws -> String
    private let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        host: String,
        email: String,
        apiToken: @escaping @Sendable () async throws -> String,
        send: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.host = host
        self.email = email
        self.apiToken = apiToken
        self.send = send
    }

    public func createTicket(
        projectKey: String,
        title: String,
        descriptionWiki: String,
        jiraIssueType: String,
        parentKey: TicketKey?
    ) async throws -> TicketKey {
        var request = try await authorizedRequest(path: "/rest/api/2/issue", method: "POST")
        request.httpBody = try JSONEncoder().encode(
            CreateIssueBody(
                fields: CreateIssueFields(
                    project: .init(key: projectKey),
                    summary: title,
                    description: descriptionWiki,
                    issuetype: .init(name: jiraIssueType),
                    parent: parentKey.map { NamedKey(key: $0.value) }
                )
            )
        )
        let (data, response) = try await perform(request)
        try requireSuccess(response)
        return TicketKey(try JSONDecoder().decode(CreateIssueResponse.self, from: data).key)
    }

    public func updateTicket(
        key: TicketKey,
        title: String,
        descriptionWiki: String,
        completenessMarker: CompletenessMarker
    ) async throws {
        var request = try await authorizedRequest(
            path: "/rest/api/2/issue/\(key.value)",
            method: "PUT"
        )
        let action = completenessMarker == .apply ? "add" : "remove"
        request.httpBody = try JSONEncoder().encode(
            UpdateIssueBody(
                fields: UpdateIssueFields(summary: title, description: descriptionWiki),
                update: LabelUpdate(labels: [[action: CompletenessMarker.jiraLabel]])
            )
        )
        let (_, response) = try await perform(request)
        try requireSuccess(response)
    }

    public func attachmentPolicy() async throws -> AttachmentPolicy {
        let request = try await authorizedRequest(
            path: "/rest/api/3/attachment/meta",
            method: "GET"
        )
        let (data, response) = try await perform(request)
        try requireSuccess(response)
        let decoded = try JSONDecoder().decode(AttachmentMetaResponse.self, from: data)
        return AttachmentPolicy(enabled: decoded.enabled, uploadLimit: decoded.uploadLimit)
    }

    public func uploadAttachment(
        key: TicketKey,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws {
        let boundary = "fakthis-\(UUID().uuidString)"
        var request = try await authorizedRequest(
            path: "/rest/api/2/issue/\(key.value)/attachments",
            method: "POST"
        )
        request.setValue("no-check", forHTTPHeaderField: "X-Atlassian-Token")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(
            Data(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                    .utf8
            )
        )
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        let (_, response) = try await perform(request)
        try requireSuccess(response)
    }

    public func fetchIssueTypes(projectKey: String) async throws -> [JiraIssueType] {
        let request = try await authorizedRequest(
            path: "/rest/api/3/issue/createmeta/\(projectKey)/issuetypes",
            method: "GET"
        )
        let (data, response) = try await perform(request)
        try requireSuccess(response)
        return try JSONDecoder().decode(CreateMetaResponse.self, from: data).issueTypes.map {
            JiraIssueType(name: $0.name, hierarchyLevel: $0.hierarchyLevel, subtask: $0.subtask)
        }
    }

    public func fetchRewriteTarget(key: TicketKey) async throws -> RewriteTarget {
        let request = try await authorizedRequest(
            path: "/rest/api/2/issue/\(key.value)",
            method: "GET"
        )
        let (data, response) = try await perform(request)
        try requireSuccess(response)
        let decoded = try JSONDecoder().decode(IssueResponse.self, from: data)
        let comments = decoded.fields.comment?.comments
            .sorted {
                (jiraDate($0.created) ?? .distantPast) > (jiraDate($1.created) ?? .distantPast)
            }
            .prefix(50)
            .map(\.body) ?? []
        return RewriteTarget(
            key: TicketKey(decoded.key),
            title: decoded.fields.summary,
            description: decoded.fields.description ?? "",
            comments: Array(comments),
            updated: jiraDate(decoded.fields.updated) ?? Date(timeIntervalSince1970: 0),
            jiraIssueType: decoded.fields.issuetype.name
        )
    }

    public func createBlocksLink(blocker: TicketKey, blocked: TicketKey) async throws {
        var request = try await authorizedRequest(path: "/rest/api/2/issueLink", method: "POST")
        request.httpBody = try JSONEncoder().encode(
            IssueLinkBody(
                type: .init(name: "Blocks"),
                inwardIssue: .init(key: blocked.value),
                outwardIssue: .init(key: blocker.value)
            )
        )
        let (_, response) = try await perform(request)
        try requireSuccess(response)
    }

    public func pullCatalog(projectKey: String) async throws -> Catalog {
        let epicKeys = try await searchKeys(
            jql: "project = \(projectKey) AND issuetype = Epic",
            maxResults: 1000
        )
        let recentKeys = try await searchKeys(
            jql: "project = \(projectKey) ORDER BY created DESC",
            maxResults: 300
        )
        let epics = try await bulkFetch(keys: epicKeys, fields: ["summary", "status"])
        let recent = try await bulkFetch(
            keys: recentKeys,
            fields: ["summary", "issuetype", "labels", "parent", "status", "created"]
        )
        let components = try await fetchComponentNames(projectKey: projectKey)
        return Catalog(
            epics: epics.map {
                CatalogEpic(key: $0.key, name: $0.summary, status: $0.status)
            },
            rows: recent.map {
                CatalogRow(
                    key: $0.key,
                    title: $0.summary,
                    jiraIssueType: $0.jiraIssueType,
                    labels: $0.labels,
                    parentEpicKey: $0.parentKey,
                    status: $0.status,
                    created: $0.created
                )
            },
            componentNames: components
        )
    }

    private func searchKeys(jql: String, maxResults: Int) async throws -> [String] {
        var keys: [String] = []
        var nextPageToken: String?
        repeat {
            var query = [
                URLQueryItem(name: "jql", value: jql),
                URLQueryItem(name: "maxResults", value: String(maxResults - keys.count)),
                URLQueryItem(name: "fields", value: "key"),
            ]
            if let nextPageToken {
                query.append(URLQueryItem(name: "nextPageToken", value: nextPageToken))
            }
            let request = try await authorizedRequest(
                path: "/rest/api/3/search/jql",
                method: "GET",
                query: query
            )
            let (data, response) = try await perform(request)
            try requireSuccess(response)
            let page = try JSONDecoder().decode(SearchResponse.self, from: data)
            keys.append(contentsOf: page.issues.map(\.key))
            if keys.count >= maxResults {
                return Array(keys.prefix(maxResults))
            }
            nextPageToken = page.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
        } while nextPageToken != nil
        return keys
    }

    private func bulkFetch(keys: [String], fields: [String]) async throws -> [SearchedIssue] {
        var fetched: [SearchedIssue] = []
        var remaining = keys[...]
        while !remaining.isEmpty {
            let chunk = Array(remaining.prefix(100))
            remaining = remaining.dropFirst(chunk.count)
            fetched.append(contentsOf: try await bulkFetchPage(keys: chunk, fields: fields))
        }
        return fetched
    }

    private func bulkFetchPage(keys: [String], fields: [String]) async throws -> [SearchedIssue] {
        var request = try await authorizedRequest(path: "/rest/api/3/issue/bulkfetch", method: "POST")
        request.httpBody = try JSONEncoder().encode(
            BulkFetchBody(issueIdsOrKeys: keys, fields: fields)
        )
        let (data, response) = try await perform(request)
        try requireSuccess(response)
        return try JSONDecoder().decode(SearchResponse.self, from: data).issues.map {
            let fields = $0.fields
            return SearchedIssue(
                key: TicketKey($0.key),
                summary: fields?.summary ?? "",
                status: fields?.status?.name ?? "",
                jiraIssueType: fields?.issuetype?.name ?? "",
                labels: fields?.labels ?? [],
                parentKey: fields?.parent.map { TicketKey($0.key) },
                created: fields?.created.flatMap(jiraDate)
            )
        }
    }

    private func fetchComponentNames(projectKey: String) async throws -> [String] {
        let request = try await authorizedRequest(
            path: "/rest/api/3/project/\(projectKey)/components",
            method: "GET"
        )
        let (data, response) = try await perform(request)
        try requireSuccess(response)
        return try JSONDecoder().decode([NamedName].self, from: data).map(\.name)
    }

    private func authorizedRequest(
        path: String,
        method: String,
        query: [URLQueryItem] = []
    ) async throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let token = Data("\(email):\(try await apiToken())".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await send(request)
        } catch is URLError {
            throw JiraUnreachable()
        }
    }

    private func requireSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JiraHTTPError(statusCode: status)
        }
    }
}

private struct CreateIssueBody: Encodable {
    var fields: CreateIssueFields
}

private struct CreateIssueFields: Encodable {
    var project: NamedKey
    var summary: String
    var description: String
    var issuetype: NamedName
    var parent: NamedKey?

    enum CodingKeys: String, CodingKey {
        case project, summary, description, issuetype, parent
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(project, forKey: .project)
        try container.encode(summary, forKey: .summary)
        try container.encode(description, forKey: .description)
        try container.encode(issuetype, forKey: .issuetype)
        try container.encodeIfPresent(parent, forKey: .parent)
    }
}

private struct NamedKey: Codable {
    var key: String
}

private struct NamedName: Codable {
    var name: String
}

private struct CreateIssueResponse: Decodable {
    var key: String
}

private struct UpdateIssueBody: Encodable {
    var fields: UpdateIssueFields
    var update: LabelUpdate
}

private struct UpdateIssueFields: Encodable {
    var summary: String
    var description: String
}

private struct LabelUpdate: Encodable {
    var labels: [[String: String]]
}

private struct AttachmentMetaResponse: Decodable {
    var enabled: Bool
    var uploadLimit: Int
}

private struct CreateMetaResponse: Decodable {
    var issueTypes: [CreateMetaIssueType]
}

private struct CreateMetaIssueType: Decodable {
    var name: String
    var hierarchyLevel: Int
    var subtask: Bool
}

private struct IssueResponse: Decodable {
    var key: String
    var fields: IssueFields
}

private struct IssueFields: Decodable {
    var summary: String
    var description: String?
    var updated: String
    var issuetype: NamedName
    var comment: IssueComments?
}

private struct IssueComments: Decodable {
    var comments: [IssueComment]
}

private struct IssueComment: Decodable {
    var body: String
    var created: String
}

private struct IssueLinkBody: Encodable {
    var type: NamedName
    var inwardIssue: NamedKey
    var outwardIssue: NamedKey
}

private func jiraDate(_ raw: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: raw) { return date }
    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    if let date = basic.date(from: raw) { return date }
    let jira = DateFormatter()
    jira.locale = Locale(identifier: "en_US_POSIX")
    jira.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    return jira.date(from: raw)
}

private struct SearchedIssue {
    var key: TicketKey
    var summary: String
    var status: String
    var jiraIssueType: String
    var labels: [String]
    var parentKey: TicketKey?
    var created: Date?
}

private struct SearchResponse: Decodable {
    var issues: [SearchIssue]
    var nextPageToken: String?
}

private struct SearchIssue: Decodable {
    var key: String
    var fields: SearchFields?
}

private struct BulkFetchBody: Encodable {
    var issueIdsOrKeys: [String]
    var fields: [String]
}

private struct SearchFields: Decodable {
    var summary: String?
    var status: NamedName?
    var issuetype: NamedName?
    var labels: [String]?
    var parent: NamedKey?
    var created: String?
}
