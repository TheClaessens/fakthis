import Foundation
import Testing
import Fakthis

@Test func modelHTTPCompletePostsChatCompletionsWithBearerAndNoTools() async throws {
    let http = ScriptedHTTP()
    await http.queue(
        status: 200,
        json: try chatCompletionJSON(content: #"{"ok":true}"#)
    )
    let model = ModelHTTP(
        apiKey: { "test-model-key" },
        send: { try await http.send($0) }
    )

    let text = try await model.complete(
        system: "Catalog\nProject terms:\nbin",
        user: "we need pickers to scan the bin",
        screenshots: []
    )

    #expect(text == #"{"ok":true}"#)
    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-model-key")
    let json = try requestJSON(request)
    #expect(json["model"] as? String == "gpt-5.6-luna")
    #expect(json["tools"] == nil)
    let messages = try #require(json["messages"] as? [[String: String]])
    #expect(messages == [
        ["role": "system", "content": "Catalog\nProject terms:\nbin"],
        ["role": "user", "content": "we need pickers to scan the bin"],
    ])
}

@Test func modelHTTPCompleteSendsScreenshotsAsImageParts() async throws {
    let http = ScriptedHTTP()
    await http.queue(
        status: 200,
        json: try chatCompletionJSON(content: #"{"ok":true}"#)
    )
    let model = ModelHTTP(
        apiKey: { "test-model-key" },
        send: { try await http.send($0) }
    )
    let png = Data("png-bytes".utf8)

    _ = try await model.complete(
        system: "rules",
        user: "scan the bin",
        screenshots: [
            Material(filename: "pick.png", mimeType: "image/png", data: png)
        ]
    )

    let json = try requestJSON(try #require(await http.requests.last))
    let messages = try #require(json["messages"] as? [[String: Any]])
    #expect(messages[0]["content"] as? String == "rules")
    let userContent = try #require(messages[1]["content"] as? [[String: Any]])
    #expect(userContent[0]["type"] as? String == "text")
    #expect(userContent[0]["text"] as? String == "scan the bin")
    #expect(userContent[1]["type"] as? String == "image_url")
    let imageURL = try #require((userContent[1]["image_url"] as? [String: String])?["url"])
    #expect(imageURL.hasPrefix("data:image/png;base64,"))
    #expect(imageURL.hasSuffix(png.base64EncodedString()))
}

@Test func modelHTTPFailsWhenTheAPIKeyCannotBeRead() async throws {
    struct MissingKey: Error {}
    let http = ScriptedHTTP()
    let model = ModelHTTP(
        apiKey: { throw MissingKey() },
        send: { try await http.send($0) }
    )

    await #expect(throws: ModelFailed.self) {
        try await model.complete(system: "prefix", user: "dump", screenshots: [])
    }
    #expect(await http.requests.isEmpty)
}

@Test func modelHTTPMapsTransportFailureToModelFailed() async throws {
    let model = ModelHTTP(
        apiKey: { "test-model-key" },
        send: { _ in throw URLError(.cannotFindHost) }
    )
    await #expect(throws: ModelFailed.self) {
        try await model.complete(system: "prefix", user: "dump", screenshots: [])
    }
}

private func chatCompletionJSON(content: String) throws -> String {
    let body: [String: Any] = [
        "choices": [
            ["message": ["content": content]]
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: body)
    return try #require(String(data: data, encoding: .utf8))
}

private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}
