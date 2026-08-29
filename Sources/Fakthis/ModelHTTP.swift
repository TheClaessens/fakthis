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

    public func complete(system: String, user: String, screenshots: [Material]) async throws -> String {
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
                    ChatMessage(role: "system", content: .text(system)),
                    ChatMessage(role: "user", content: .user(text: user, screenshots: screenshots)),
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
    var content: Content

    enum Content: Encodable {
        case text(String)
        case user(text: String, screenshots: [Material])

        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let text):
                var container = encoder.singleValueContainer()
                try container.encode(text)
            case .user(let text, let screenshots) where screenshots.isEmpty:
                var container = encoder.singleValueContainer()
                try container.encode(text)
            case .user(let text, let screenshots):
                var container = encoder.unkeyedContainer()
                try container.encode(ContentPart(type: "text", text: text, imageURL: nil))
                for screenshot in screenshots {
                    let encoded = screenshot.data.base64EncodedString()
                    try container.encode(
                        ContentPart(
                            type: "image_url",
                            text: nil,
                            imageURL: ImageURL(url: "data:\(screenshot.mimeType);base64,\(encoded)")
                        )
                    )
                }
            }
        }
    }

    private struct ContentPart: Encodable {
        var type: String
        var text: String?
        var imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encodeIfPresent(imageURL, forKey: .imageURL)
        }
    }

    private struct ImageURL: Encodable {
        var url: String
    }
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
