import Foundation
import os
import Testing
@testable import AIFormatKit

/// A provider driven by a closure that also counts its calls.
final class FakeProvider: FormatProvider, @unchecked Sendable {
    private let calls = OSAllocatedUnfairLock(initialState: 0)
    private let handler: @Sendable (_ system: String, _ user: String) async throws -> String

    init(_ handler: @escaping @Sendable (_ system: String, _ user: String) async throws -> String) {
        self.handler = handler
    }

    var callCount: Int { calls.withLock { $0 } }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        calls.withLock { $0 += 1 }
        return try await handler(system, user)
    }
}

@Suite struct FormatPipelineTests {
    @Test func endToEndRestoresProtectedContent() async throws {
        let original = "周报\n\n本周完成了重构，见 `Refactor.swift`。\n\n```swift\nlet value = 42 // 保持原样\n```"
        // The "model" turns the first line into a heading and echoes everything else, placeholders included.
        let provider = FakeProvider { _, user in "# " + user }
        let outcome = try await FormatPipeline(provider: provider, extraInstructions: "").run(original, isFragment: false)

        #expect(outcome.formatted.hasPrefix("# 周报"))
        #expect(outcome.formatted.contains("```swift\nlet value = 42 // 保持原样\n```"))
        #expect(outcome.formatted.contains("`Refactor.swift`"))
        #expect(outcome.guardResult.passed)
        #expect(outcome.diff.changes[0] == .becameHeading)
        #expect(outcome.hasChanges)
    }

    @Test func promptReachesTheProvider() async throws {
        let seen = OSAllocatedUnfairLock(initialState: "")
        let provider = FakeProvider { system, user in
            seen.withLock { $0 = system }
            return user
        }
        _ = try await FormatPipeline(provider: provider, extraInstructions: "列表一律用 -").run("正文", isFragment: true)
        let system = seen.withLock { $0 }
        #expect(system.contains("列表一律用 -"))
        #expect(system.contains("fragment of a larger document"))
    }

    @Test func sendsPlaceholdersNotProtectedContent() async throws {
        let seen = OSAllocatedUnfairLock(initialState: "")
        let provider = FakeProvider { _, user in
            seen.withLock { $0 = user }
            return user
        }
        _ = try await FormatPipeline(provider: provider, extraInstructions: "").run("看 https://secret.example/x 和 `code`", isFragment: false)
        let sent = seen.withLock { $0 }
        #expect(!sent.contains("secret.example"))
        #expect(!sent.contains("`code`"))
        #expect(sent.contains("⟦TN:0⟧"))
    }

    @Test func incompleteWhenPlaceholderDropped() async throws {
        let provider = FakeProvider { _, user in user.replacingOccurrences(of: "⟦TN:0⟧", with: "") }
        await #expect(throws: AIError.incompleteResult) {
            try await FormatPipeline(provider: provider, extraInstructions: "").run("调用 `foo()` 即可", isFragment: false)
        }
    }

    @Test func fencedAnswerIsUnwrapped() async throws {
        let provider = FakeProvider { _, user in "```markdown\n# " + user + "\n```" }
        let outcome = try await FormatPipeline(provider: provider, extraInstructions: "").run("标题", isFragment: false)
        #expect(outcome.formatted == "# 标题")
    }

    @Test func chunksAreFormattedAndJoined() async throws {
        let paragraphs = (0..<270).map { "第 \($0) 段：" + String(repeating: "字", count: 42) }
        let original = paragraphs.joined(separator: "\n\n")
        #expect(original.utf16.count > 13_000)
        let provider = FakeProvider { _, user in user }
        let outcome = try await FormatPipeline(provider: provider, extraInstructions: "").run(original, isFragment: false)
        #expect(provider.callCount >= 3)
        #expect(outcome.formatted == original)
        #expect(!outcome.hasChanges)
    }

    @Test func leadingAndTrailingWhitespaceSurvive() async throws {
        let provider = FakeProvider { _, user in user }
        let outcome = try await FormatPipeline(provider: provider, extraInstructions: "").run("\n\n正文\n\n", isFragment: false)
        #expect(outcome.formatted == "\n\n正文\n\n")
    }

    @Test func cancellationStops() async throws {
        let provider = FakeProvider { _, user in
            try await Task.sleep(for: .seconds(5))
            return user
        }
        let paragraphs = (0..<270).map { "第 \($0) 段：" + String(repeating: "字", count: 42) }
        let original = paragraphs.joined(separator: "\n\n")
        let task = Task {
            try await FormatPipeline(provider: provider, extraInstructions: "").run(original, isFragment: false)
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(provider.callCount <= 1)
    }

    @Test func staleTokenDetected() {
        // Review Focus 3: text edited while the request was running must not be overwritten by its result.
        let token = FormatRequestToken(text: "a")
        #expect(token.isStale(currentText: "ab"))
        #expect(!token.isStale(currentText: "a"))
    }

    @Test func noChangeOutcome() async throws {
        let provider = FakeProvider { _, user in user }
        let outcome = try await FormatPipeline(provider: provider, extraInstructions: "").run("# 标题\n\n正文。", isFragment: false)
        #expect(!outcome.hasChanges)
    }

    @Test func providerErrorsPropagate() async throws {
        let provider = FakeProvider { _, _ in throw AIError.rateLimited }
        await #expect(throws: AIError.rateLimited) {
            try await FormatPipeline(provider: provider, extraInstructions: "").run("正文", isFragment: false)
        }
    }

    @Test func rewordedTextFailsTheGuardButStillReturns() async throws {
        let provider = FakeProvider { _, _ in "我认为很好" }
        let outcome = try await FormatPipeline(provider: provider, extraInstructions: "").run("我觉得不错", isFragment: false)
        #expect(!outcome.guardResult.passed)
    }
}
