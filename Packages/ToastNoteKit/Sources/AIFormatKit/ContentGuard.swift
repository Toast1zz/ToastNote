import Foundation

public struct GuardResult: Equatable, Sendable {
    public var passed: Bool
    /// Sentences around the changes, for the review window to list when the check fails.
    public var changedSentences: [String]

    public init(passed: Bool, changedSentences: [String]) {
        self.passed = passed
        self.changedSentences = changedSentences
    }
}

/// Checks that formatting changed structure only (spec §8.5): the text a reader sees, minus whitespace,
/// punctuation and case, must match, allowing a few stray characters.
public enum ContentGuard {
    /// Every change run may be at most this many characters …
    static let maxRunLength = 2
    /// … and all changes together at most this share of the original text.
    static let maxTotalShare = 0.01
    /// Texts whose normalized lengths differ by more than this share fail without being diffed.
    static let lengthGate = 0.10
    /// Below this many normalized characters a failed length gate still produces a sentence list.
    static let shortTextLimit = 400

    private struct Normalized {
        var characters: [Character] = []
        /// Offset into the plain text for each normalized character, to find the sentence again.
        var plainOffsets: [Int] = []
        var plain: String
    }

    public static func check(original: String, formatted: String) -> GuardResult {
        let before = normalize(PlainText.extract(original))
        let after = normalize(PlainText.extract(formatted))

        // Texts of very different length cannot pass. Large ones fail at once instead of being diffed; short
        // ones are still diffed (cheaply) so the review window can list what changed.
        let lengthDifference = abs(before.characters.count - after.characters.count)
        let lengthsDiffer = Double(lengthDifference) > lengthGate * Double(max(before.characters.count, 1))
        if lengthsDiffer, max(before.characters.count, after.characters.count) > shortTextLimit {
            return GuardResult(passed: false, changedSentences: [])
        }

        let difference = after.characters.difference(from: before.characters)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        // Walk both texts together; a run is a stretch of removals and insertions without a match between.
        var runs: [(removed: [Int], inserted: [Int])] = []
        var i = 0, j = 0
        while i < before.characters.count || j < after.characters.count {
            if removed.contains(i) || inserted.contains(j) {
                var run: (removed: [Int], inserted: [Int]) = ([], [])
                while i < before.characters.count, removed.contains(i) { run.removed.append(i); i += 1 }
                while j < after.characters.count, inserted.contains(j) { run.inserted.append(j); j += 1 }
                runs.append(run)
            } else {
                i += 1
                j += 1
            }
        }

        let longestRun = runs.map { max($0.removed.count, $0.inserted.count) }.max() ?? 0
        let totalChanged = runs.reduce(0) { $0 + $1.removed.count + $1.inserted.count }
        let allowedTotal = maxTotalShare * Double(before.characters.count)
        let passed = !lengthsDiffer && longestRun <= maxRunLength && Double(totalChanged) <= allowedTotal
        guard !passed else { return GuardResult(passed: true, changedSentences: []) }

        var sentences: [String] = []
        for run in runs {
            let sentence: String?
            if let first = run.removed.first {
                sentence = Self.sentence(containing: before.plainOffsets[first], in: before.plain)
            } else if let first = run.inserted.first {
                sentence = Self.sentence(containing: after.plainOffsets[first], in: after.plain)
            } else {
                sentence = nil
            }
            if let sentence, !sentence.isEmpty, !sentences.contains(sentence) { sentences.append(sentence) }
        }
        return GuardResult(passed: false, changedSentences: sentences)
    }

    /// Drops whitespace and Unicode punctuation, lowercases, and remembers where each character came from.
    private static func normalize(_ plain: String) -> Normalized {
        var result = Normalized(plain: plain)
        var offset = 0
        for character in plain {
            defer { offset += character.utf16.count }
            if character.isWhitespace || character.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
                continue
            }
            for lowered in String(character).lowercased() {
                result.characters.append(lowered)
                result.plainOffsets.append(offset)
            }
        }
        return result
    }

    private static let sentenceEnds: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n"]

    private static func sentence(containing utf16Offset: Int, in text: String) -> String {
        let ns = text as NSString
        guard utf16Offset < ns.length else { return "" }
        var start = utf16Offset
        while start > 0, !sentenceEnds.contains(Character(UnicodeScalar(ns.character(at: start - 1)) ?? " ")) { start -= 1 }
        var end = utf16Offset
        while end < ns.length, !sentenceEnds.contains(Character(UnicodeScalar(ns.character(at: end)) ?? " ")) { end += 1 }
        if end < ns.length { end += 1 }  // keep the closing punctuation
        return ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
