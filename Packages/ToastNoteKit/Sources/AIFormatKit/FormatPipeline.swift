import Foundation

public struct FormatOutcome: Equatable, Sendable {
    public var original: String
    public var formatted: String
    public var guardResult: GuardResult
    public var diff: BlockDiffResult
    public var hasChanges: Bool { !diff.changes.isEmpty || formatted != original }
}

/// Snapshot of the text a request was started for. If the text moved on while the request ran, the
/// result is discarded rather than applied over newer edits (spec §8.7, Review Focus 3).
public struct FormatRequestToken: Equatable, Sendable {
    private let text: String

    public init(text: String) {
        self.text = text
    }

    public func isStale(currentText: String) -> Bool {
        currentText != text
    }
}

/// protect → chunk → ask the model for each chunk → restore → check → diff (spec §8.1).
public struct FormatPipeline: Sendable {
    private let provider: FormatProvider
    private let extraInstructions: String

    public init(provider: FormatProvider, extraInstructions: String) {
        self.provider = provider
        self.extraInstructions = extraInstructions
    }

    /// Honors task cancellation between and during requests.
    public func run(_ text: String, isFragment: Bool) async throws -> FormatOutcome {
        let protected = Protector.protect(text)
        let system = PromptBuilder.system(extra: extraInstructions, isFragment: isFragment)

        var answers: [String] = []
        for chunk in Chunker.split(protected.text) {
            try Task.checkCancellation()
            let reply = try await provider.complete(system: system, user: chunk, maxTokens: TokenBudget.maxTokens(forInput: chunk))
            try Task.checkCancellation()
            answers.append(ResponseCleaner.clean(reply))
        }

        // Cleaning trims the answer; the note keeps whatever blank lines it began and ended with.
        let leading = String(text.prefix(while: { $0.isWhitespace || $0.isNewline }))
        let trailing = String(text.reversed().prefix(while: { $0.isWhitespace || $0.isNewline }).reversed())
        let body = try Protector.restore(answers.joined(separator: "\n\n"), slots: protected.slots)
        let formatted = text.allSatisfy({ $0.isWhitespace }) ? text : leading + body + trailing

        return FormatOutcome(
            original: text,
            formatted: formatted,
            guardResult: ContentGuard.check(original: text, formatted: formatted),
            diff: BlockDiff.compare(original: text, formatted: formatted)
        )
    }
}
