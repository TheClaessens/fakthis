import Foundation

/// The model providers Fakthis can reach, and the one thing that differs between them: where a
/// completion is sent. `ModelHTTP` speaks one wire format — OpenAI's chat completions — so a
/// provider is a name and an endpoint that speaks it. A provider with its own wire format is a
/// second adapter, not another case here.
///
/// The provider is picked at first launch and stored as its raw value in `settings.json`;
/// §13's cheap-tier defaults are model ids typed into the field beside it, not cases.
enum ModelProvider: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case openRouter = "openrouter"

    /// §13 pins an alias on a cheap tier, never a snapshot, and this is the one the setup form
    /// starts on.
    static let defaultModelId = "gpt-5.6-luna"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        }
    }

    var completions: URL {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .openRouter: URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        }
    }

    /// What a settings file already holds. A name this build does not know reads back as the
    /// default rather than leaving Generate with nowhere to send a completion.
    init(stored: String) {
        self = ModelProvider(rawValue: stored) ?? .openAI
    }
}
