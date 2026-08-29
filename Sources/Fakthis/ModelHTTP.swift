import Foundation

public actor ModelHTTP: Model {
    private let endpoint: URL
    private let modelId: String
    private let apiKey: @Sendable () async throws -> String
    private let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        modelId: String = "gpt-5.6-luna",
        apiKey: @escaping @Sendable () async throws -> String,
        send: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.endpoint = endpoint
        self.modelId = modelId
        self.apiKey = apiKey
        self.send = send
    }

    public func complete(system: String, user: String) async throws -> String {
        let key: String
        do {
            key = try await apiKey()
        } catch {
            throw ModelFailed()
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: modelId,
                messages: [
                    ChatMessage(role: "system", content: system),
                    ChatMessage(role: "user", content: user),
                ]
            )
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch {
            throw ModelFailed()
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let text = try? JSONDecoder().decode(ChatResponse.self, from: data).assistantText
        else {
            throw ModelFailed()
        }
        return text
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
}

private struct ChatMessage: Encodable {
    var role: String
    var content: String
}

private struct ChatResponse: Decodable {
    var choices: [Choice]

    var assistantText: String? { choices.first?.message.content }

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String
    }
}
