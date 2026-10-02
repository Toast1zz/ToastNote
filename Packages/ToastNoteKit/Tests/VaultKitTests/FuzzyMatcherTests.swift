import Foundation
import Testing
@testable import VaultKit

@Suite struct FuzzyMatcherTests {
    @Test func subsequenceMatches() {
        #expect(FuzzyMatcher.score(query: "dsn", candidate: "design") != nil)
        #expect(FuzzyMatcher.score(query: "xyz", candidate: "design") == nil)
    }

    @Test func noPinyinSupport() {
        // Documented limitation: matching is on characters, so "zb" does not find 周报.
        #expect(FuzzyMatcher.score(query: "zb", candidate: "周报") == nil)
    }

    @Test func chineseSubsequence() {
        #expect(FuzzyMatcher.score(query: "周报", candidate: "产品周报") != nil)
        #expect(FuzzyMatcher.score(query: "品报", candidate: "产品周报") != nil)
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatcher.score(query: "", candidate: "abc") == 0)
    }

    @Test func caseAndWidthInsensitive() {
        #expect(FuzzyMatcher.score(query: "DESIGN", candidate: "design") != nil)
        #expect(FuzzyMatcher.score(query: "ａｂ", candidate: "ab") != nil)  // full-width letters
    }

    @Test func contiguousBeatsScattered() throws {
        let contiguous = try #require(FuzzyMatcher.score(query: "设计", candidate: "设计"))
        let scattered = try #require(FuzzyMatcher.score(query: "设计", candidate: "设x计"))
        #expect(contiguous > scattered)
    }

    @Test func wordStartBonus() throws {
        let start = try #require(FuzzyMatcher.score(query: "ds", candidate: "design-system"))
        let middle = try #require(FuzzyMatcher.score(query: "ds", candidate: "ads"))
        #expect(start > middle)
    }

    @Test func titleBeatsPath() {
        let notes = [
            NoteRef(path: "设计/杂项.md", title: "杂项"),
            NoteRef(path: "杂项/设计.md", title: "设计"),
        ]
        #expect(FuzzyMatcher.rank(query: "设计", candidates: notes).first?.title == "设计")
    }

    @Test func pathIsAFallbackWhenTitleDoesNotMatch() {
        let notes = [NoteRef(path: "工作/周报.md", title: "周报")]
        #expect(FuzzyMatcher.rank(query: "工作", candidates: notes).count == 1)
    }

    @Test func ties_preferShorterPath() {
        let notes = [
            NoteRef(path: "a/b/c/笔记.md", title: "笔记"),
            NoteRef(path: "笔记.md", title: "笔记"),
        ]
        #expect(FuzzyMatcher.rank(query: "笔记", candidates: notes).first?.path == "笔记.md")
    }

    @Test func limitRespected() {
        let notes = (0..<100).map { NoteRef(path: "n\($0).md", title: "n\($0)") }
        #expect(FuzzyMatcher.rank(query: "n", candidates: notes, limit: 50).count == 50)
        #expect(FuzzyMatcher.rank(query: "n", candidates: notes, limit: 7).count == 7)
    }

    @Test func nonMatchesAreDropped() {
        let notes = [NoteRef(path: "a.md", title: "a"), NoteRef(path: "b.md", title: "b")]
        #expect(FuzzyMatcher.rank(query: "a", candidates: notes).map(\.title) == ["a"])
    }
}
