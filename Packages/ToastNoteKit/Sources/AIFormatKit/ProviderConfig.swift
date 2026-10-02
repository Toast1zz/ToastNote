import Foundation

public enum ProviderKind: String, Codable, Sendable {
    case anthropic
    case openAICompatible
}

public struct ProviderConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: ProviderKind
    public var baseURL: String
    public var model: String
    public var requiresKey: Bool

    public init(id: String, name: String, kind: ProviderKind, baseURL: String, model: String, requiresKey: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.requiresKey = requiresKey
    }
}

/// The built-in providers of spec §8.2, DeepSeek first. Models other than DeepSeek's and Anthropic's are
/// left empty for the user to fill in.
public enum ProviderPresets {
    public static let all: [ProviderConfig] = [
        ProviderConfig(id: "deepseek", name: "DeepSeek", kind: .openAICompatible, baseURL: "https://api.deepseek.com", model: "deepseek-flash", requiresKey: true),
        ProviderConfig(id: "anthropic", name: "Anthropic", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude-haiku-4-5", requiresKey: true),
        ProviderConfig(id: "openai", name: "OpenAI", kind: .openAICompatible, baseURL: "https://api.openai.com/v1", model: "", requiresKey: true),
        ProviderConfig(id: "openrouter", name: "OpenRouter", kind: .openAICompatible, baseURL: "https://openrouter.ai/api/v1", model: "", requiresKey: true),
        ProviderConfig(id: "ollama", name: "Ollama（本地）", kind: .openAICompatible, baseURL: "http://localhost:11434/v1", model: "", requiresKey: false),
    ]

    /// Ids of presets shipped earlier and since removed; stored copies are dropped on load.
    public static let retiredIDs: Set<String> = ["siliconflow", "dashscope"]
}
