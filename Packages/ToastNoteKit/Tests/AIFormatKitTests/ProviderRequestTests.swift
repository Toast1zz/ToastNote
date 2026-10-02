import Foundation
import os
import Testing
@testable import AIFormatKit

/// Records the request and returns canned responses; tests never touch the network.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let recorded = OSAllocatedUnfairLock(initialState: [URLRequest]())
    var status = 200
    var body = Data()
    var error: Error?

    var requests: [URLRequest] { recorded.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        if let error { throw error }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

private func json(_ data: Data?) throws -> [String: Any] {
    let data = try #require(data)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private let anthropicConfig = ProviderConfig(id: "anthropic", name: "Anthropic", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude-haiku-4-5", requiresKey: true)
private let deepseekConfig = ProviderConfig(id: "deepseek", name: "DeepSeek", kind: .openAICompatible, baseURL: "https://api.deepseek.com", model: "deepseek-flash", requiresKey: true)
private let ollamaConfig = ProviderConfig(id: "ollama", name: "Ollama", kind: .openAICompatible, baseURL: "http://localhost:11434/v1", model: "qwen", requiresKey: false)

struct StatusCase: Sendable, CustomTestStringConvertible {
    let status: Int
    let expected: AIError
    var testDescription: String { "HTTP \(status)" }
}

@Suite struct ProviderRequestTests {
    @Test func anthropicRequestShape() async throws {
        let client = FakeHTTPClient()
        client.body = Data(#"{"content":[{"type":"text","text":"ok"}]}"#.utf8)
        let provider = makeProvider(anthropicConfig, apiKey: "k-1", client: client)
        _ = try await provider.complete(system: "SYS", user: "USER", maxTokens: 500)

        let request = try #require(client.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "k-1")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
        let body = try json(request.httpBody)
        #expect(body["model"] as? String == "claude-haiku-4-5")
        #expect(body["max_tokens"] as? Int == 500)
        #expect(body["temperature"] as? Double == 0)
        #expect(body["system"] as? String == "SYS")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "USER"]])
    }

    @Test func anthropicParsesText() async throws {
        let client = FakeHTTPClient()
        client.body = Data(##"{"content":[{"type":"text","text":"# A"},{"type":"text","text":"\n\nb"}]}"##.utf8)
        let provider = makeProvider(anthropicConfig, apiKey: "k", client: client)
        #expect(try await provider.complete(system: "s", user: "u", maxTokens: 10) == "# A\n\nb")
    }

    @Test func openAIRequestShape() async throws {
        let client = FakeHTTPClient()
        client.body = Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8)
        let provider = makeProvider(deepseekConfig, apiKey: "k", client: client)
        _ = try await provider.complete(system: "SYS", user: "USER", maxTokens: 321)

        let request = try #require(client.requests.first)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        let body = try json(request.httpBody)
        #expect(body["model"] as? String == "deepseek-flash")
        #expect(body["temperature"] as? Double == 0)
        #expect(body["max_tokens"] as? Int == 321)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "SYS"], ["role": "user", "content": "USER"]])
    }

    @Test func openAIParsesText() async throws {
        let client = FakeHTTPClient()
        client.body = Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8)
        let provider = makeProvider(deepseekConfig, apiKey: "k", client: client)
        #expect(try await provider.complete(system: "s", user: "u", maxTokens: 10) == "x")
    }

    @Test func ollamaOmitsAuthHeader() async throws {
        let client = FakeHTTPClient()
        client.body = Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8)
        let provider = makeProvider(ollamaConfig, apiKey: nil, client: client)
        _ = try await provider.complete(system: "s", user: "u", maxTokens: 10)
        let request = try #require(client.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
    }

    @Test func missingKeyForAProviderThatNeedsOneIsNotConfigured() async throws {
        let client = FakeHTTPClient()
        let provider = makeProvider(deepseekConfig, apiKey: "", client: client)
        await #expect(throws: AIError.notConfigured) { try await provider.complete(system: "s", user: "u", maxTokens: 10) }
        #expect(client.requests.isEmpty)
    }

    @Test(arguments: [
        StatusCase(status: 401, expected: .unauthorized),
        StatusCase(status: 403, expected: .unauthorized),
        StatusCase(status: 404, expected: .modelNotFound("deepseek-flash")),
        StatusCase(status: 429, expected: .rateLimited),
        StatusCase(status: 500, expected: .network),
    ])
    func mapsStatus(_ testCase: StatusCase) async throws {
        let client = FakeHTTPClient()
        client.status = testCase.status
        client.body = Data("{}".utf8)
        let provider = makeProvider(deepseekConfig, apiKey: "k", client: client)
        await #expect(throws: testCase.expected) { try await provider.complete(system: "s", user: "u", maxTokens: 10) }
    }

    @Test func mapsURLErrorTimeout() async throws {
        let client = FakeHTTPClient()
        client.error = URLError(.timedOut)
        let provider = makeProvider(deepseekConfig, apiKey: "k", client: client)
        await #expect(throws: AIError.timeout) { try await provider.complete(system: "s", user: "u", maxTokens: 10) }
    }

    @Test func otherURLErrorsAreNetworkErrors() async throws {
        let client = FakeHTTPClient()
        client.error = URLError(.notConnectedToInternet)
        let provider = makeProvider(deepseekConfig, apiKey: "k", client: client)
        await #expect(throws: AIError.network) { try await provider.complete(system: "s", user: "u", maxTokens: 10) }
    }

    @Test func unparseableBodyIsAnIncompleteResult() async throws {
        let client = FakeHTTPClient()
        client.body = Data("<html>".utf8)
        let provider = makeProvider(deepseekConfig, apiKey: "k", client: client)
        await #expect(throws: AIError.incompleteResult) { try await provider.complete(system: "s", user: "u", maxTokens: 10) }
    }

    @Test func baseURLTrailingSlashTolerated() async throws {
        let client = FakeHTTPClient()
        client.body = Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8)
        var config = deepseekConfig
        config.baseURL = "https://api.deepseek.com/"
        _ = try await makeProvider(config, apiKey: "k", client: client).complete(system: "s", user: "u", maxTokens: 10)
        #expect(client.requests.first?.url?.absoluteString == "https://api.deepseek.com/chat/completions")
    }

    @Test func tokenBudgetFollowsInputLength() {
        // utf8 bytes / 3, doubled, plus 1024, capped at 16000 (spec §8.2).
        #expect(TokenBudget.maxTokens(forInput: String(repeating: "a", count: 300)) == 100 * 2 + 1024)
        #expect(TokenBudget.maxTokens(forInput: String(repeating: "中", count: 100)) == 100 * 2 + 1024)  // 300 bytes
        #expect(TokenBudget.maxTokens(forInput: String(repeating: "a", count: 100_000)) == 16000)
        #expect(TokenBudget.maxTokens(forInput: "") == 1024)
    }
}
