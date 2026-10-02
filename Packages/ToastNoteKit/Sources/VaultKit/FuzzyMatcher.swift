import Foundation

/// Subsequence matcher for quick open (spec §10.2). It matches characters, so there is no pinyin support:
/// typing "zb" does not find 周报.
public enum FuzzyMatcher {
    /// nil means the query is not a subsequence of the candidate. Case and character width are ignored.
    public static func score(query: String, candidate: String) -> Int? {
        let needle = Array(fold(query))
        let haystack = Array(fold(candidate))
        guard !needle.isEmpty else { return 0 }

        var score = 0
        var position = 0
        var previousMatch = -1
        for char in needle {
            guard let found = (position..<haystack.count).first(where: { haystack[$0] == char }) else { return nil }
            score += 10
            if found == previousMatch + 1, previousMatch >= 0 { score += 15 }
            if found == 0 || isWordBoundary(haystack[found - 1]) { score += 20 }
            score -= found - position  // characters skipped to reach this match
            previousMatch = found
            position = found + 1
        }
        return score
    }

    /// Notes whose title matches come first, then notes that only match by path; ties go to the shorter path.
    public static func rank(query: String, candidates: [NoteRef], limit: Int = 50) -> [NoteRef] {
        var scored: [(note: NoteRef, score: Int)] = []
        for note in candidates {
            if let titleScore = score(query: query, candidate: note.title) {
                scored.append((note, titleScore + 1000))
            } else if let pathScore = score(query: query, candidate: note.path) {
                scored.append((note, pathScore))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.note.path.count < rhs.note.path.count
        }
        return scored.prefix(limit).map(\.note)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    private static func isWordBoundary(_ char: Character) -> Bool {
        char == "/" || char == "-" || char == "_" || char == " " || char == "."
    }
}
