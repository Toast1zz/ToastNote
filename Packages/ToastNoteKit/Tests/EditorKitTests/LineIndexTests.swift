import Foundation
import Markdown
import Testing
@testable import EditorKit

@Suite struct LineIndexTests {
    @Test func asciiColumns() {
        #expect(LineIndex("ab\ncd").utf16Offset(line: 2, column: 1) == 3)
    }

    @Test func cjkColumns() {
        // "中" is 3 UTF-8 bytes but 1 UTF-16 unit.
        #expect(LineIndex("中文\nx").utf16Offset(line: 1, column: 4) == 1)
    }

    @Test func cjkOnSecondLine() {
        // line 1 is 3 UTF-16 units + newline, so line 2 starts at 3
        #expect(LineIndex("ab\n中文").utf16Offset(line: 2, column: 4) == 4)
    }

    @Test func emojiColumns() {
        // 😀 is 4 UTF-8 bytes and 2 UTF-16 units.
        #expect(LineIndex("😀a").utf16Offset(line: 1, column: 5) == 2)
    }

    @Test func endOfTextColumn() {
        #expect(LineIndex("ab").utf16Offset(line: 1, column: 3) == 2)
    }

    @Test func columnPastLineEndClampsToLineEnd() {
        #expect(LineIndex("ab\ncd").utf16Offset(line: 1, column: 99) == 2)
    }

    @Test func linePastEndClampsToTextEnd() {
        #expect(LineIndex("ab").utf16Offset(line: 5, column: 1) == 2)
    }

    @Test func parsedHeadingRange() throws {
        let text = "# 中文标题\n"
        let document = Document(parsing: text)
        let heading = try #require(document.children.first(where: { $0 is Heading }))
        let range = try #require(heading.range)
        #expect(LineIndex(text).nsRange(range) == NSRange(location: 0, length: 6))
    }

    @Test func parsedRangeAfterEmojiLine() throws {
        let text = "😀 开头\n\n## 标题"
        let document = Document(parsing: text)
        let heading = try #require(document.children.first(where: { $0 is Heading }))
        let range = try #require(heading.range)
        let ns = LineIndex(text).nsRange(range)
        #expect((text as NSString).substring(with: ns) == "## 标题")
    }
}
