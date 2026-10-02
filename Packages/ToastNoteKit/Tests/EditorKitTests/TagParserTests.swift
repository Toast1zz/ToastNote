import Foundation
import Testing
@testable import EditorKit

@Suite struct TagParserTests {
    private func names(_ text: String, excluding: [NSRange] = []) -> [String] {
        TagParser.tags(in: text, excluding: excluding).map(\.tag)
    }

    @Test func chineseTag() {
        let result = TagParser.tags(in: "看 #工作 吧")
        #expect(result.map(\.tag) == ["工作"])
        #expect(result[0].range == NSRange(location: 2, length: 3))
    }

    @Test func nestedTag() {
        #expect(names("#a/b/c") == ["a/b/c"])
    }

    @Test func tagAtLineStartAndAfterWhitespace() {
        #expect(names("#one\ntext #two\tand #three") == ["one", "two", "three"])
    }

    @Test func midWordHashIgnored() {
        #expect(names("C#语言") == [])
    }

    @Test func headingNotTag() {
        #expect(names("# 标题\n## 小标题") == [])
    }

    @Test func numericIgnored() {
        #expect(names("#123 and #4a") == ["4a"])
    }

    @Test func underscoreAndDashAllowed() {
        #expect(names("#my_tag-2") == ["my_tag-2"])
    }

    @Test func excludedRangesSkipped() {
        let text = "`#code` #real"
        #expect(names(text, excluding: [NSRange(location: 0, length: 7)]) == ["real"])
    }

    @Test func emojiBeforeTagKeepsUTF16Ranges() {
        let result = TagParser.tags(in: "😀 #x")
        #expect(result[0].range == NSRange(location: 3, length: 2))
    }
}
