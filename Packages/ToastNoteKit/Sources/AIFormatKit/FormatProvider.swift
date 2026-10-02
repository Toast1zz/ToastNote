import Foundation

/// One non-streaming completion: a system prompt and a user message in, text out.
public protocol FormatProvider: Sendable {
    func complete(system: String, user: String, maxTokens: Int) async throws -> String
}

public func makeProvider(_ config: ProviderConfig, apiKey: String?, client: HTTPClient) -> FormatProvider {
    switch config.kind {
    case .anthropic:
        AnthropicProvider(config: config, apiKey: apiKey, client: client)
    case .openAICompatible:
        OpenAICompatibleProvider(config: config, apiKey: apiKey, client: client)
    }
}

/// Output budget for a formatting request (spec §8.2): twice the estimated input tokens plus 1024, at most 16000.
public enum TokenBudget {
    public static func maxTokens(forInput text: String) -> Int {
        let estimate = text.utf8.count / 3
        return min(estimate * 2 + 1024, 16000)
    }
}

/// Request plumbing shared by both adapters: URL building, the call itself and error mapping.
struct ProviderTransport {
    let config: ProviderConfig
    let apiKey: String?
    let client: HTTPClient

    /// `base` with no trailing slash, plus `path`.
    func url(_ path: String) -> URL? {
        var base = config.baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }

    var hasKey: Bool { !(apiKey ?? "").isEmpty }

    func post(_ path: String, headers: [String: String], body: [String: Any]) async throws -> Data {
        guard config.requiresKey == false || hasKey, let url = url(path) else { throw AIError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await client.send(request)
        } catch let error as URLError where error.code == .timedOut {
            throw AIError.timeout
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AIError.network
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw AIError.unauthorized
        case 404: throw AIError.modelNotFound(config.model)
        case 429: throw AIError.rateLimited
        default: throw AIError.network
        }
    }
}

struct AnthropicProvider: FormatProvider {
    let config: ProviderConfig
    let apiKey: String?
    let client: HTTPClient

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        let transport = ProviderTransport(config: config, apiKey: apiKey, client: client)
        let data = try await transport.post(
            "/v1/messages",
            headers: ["x-api-key": apiKey ?? "", "anthropic-version": "2023-06-01"],
            body: [
                "model": config.model,
                "max_tokens": maxTokens,
                "temperature": 0,
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
        )
        struct Reply: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw AIError.incompleteResult }
        let text = reply.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw AIError.incompleteResult }
        return text
    }
}

struct OpenAICompatibleProvider: FormatProvider {
    let config: ProviderConfig
    let apiKey: String?
    let client: HTTPClient

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        let transport = ProviderTransport(config: config, apiKey: apiKey, client: client)
        var headers: [String: String] = [:]
        if transport.hasKey { headers["Authorization"] = "Bearer \(apiKey ?? "")" }
        let data = try await transport.post(
            "/chat/completions",
            headers: headers,
            body: [
                "model": config.model,
                "temperature": 0,
                "max_tokens": maxTokens,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            ]
        )
        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let text = reply.choices.first?.message.content, !text.isEmpty else { throw AIError.incompleteResult }
        return text
    }
}
