import Foundation

public enum AIError: Error, Equatable, Sendable {
    /// No provider, or a provider that needs an API key has none.
    case notConfigured
    /// 401 / 403.
    case unauthorized
    /// 404: the model name does not exist for this provider.
    case modelNotFound(String)
    /// 429.
    case rateLimited
    case network
    case timeout
    /// A protected placeholder came back missing or duplicated, or the answer could not be read.
    case incompleteResult
    /// The text changed while the request was running.
    case textChanged
}
