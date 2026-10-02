import Foundation
import Testing
@testable import EditorKit

@Suite struct FrontmatterParserTests {
    @Test func splitsFrontmatterAndBody() {
        let text = "---\ntags: [a]\n---\n正文"
        let (range, body) = FrontmatterParser.split(text)
        #expect(range == NSRange(location: 0, length: 17))
        #expect(body == "正文")
    }

    @Test func noFrontmatterWhenNotAtStart() {
        let text = "intro\n---\ntags: [a]\n---\n"
        let (range, body) = FrontmatterParser.split(text)
        #expect(range == nil)
        #expect(String(body) == text)
        #expect(FrontmatterParser.tags(in: text) == [])
    }

    @Test func unclosedFrontmatterIsNotFrontmatter() {
        let (range, _) = FrontmatterParser.split("---\ntags: [a]\n正文")
        #expect(range == nil)
    }

    @Test func flowList() {
        #expect(FrontmatterParser.tags(in: "---\ntags: [a, b]\n---\n") == ["a", "b"])
    }

    @Test func blockList() {
        #expect(FrontmatterParser.tags(in: "---\ntitle: x\ntags:\n  - a\n  - 工作/周报\nother: 1\n---\n") == ["a", "工作/周报"])
    }

    @Test func quotedValues() {
        #expect(FrontmatterParser.tags(in: "---\ntags: [\"a b\", 'c']\n---\n") == ["a b", "c"])
    }

    @Test func commaSeparatedScalarIsNotSupported() {
        #expect(FrontmatterParser.tags(in: "---\ntags: a, b\n---\n") == [])
    }

    @Test func leadingHashStripped() {
        #expect(FrontmatterParser.tags(in: "---\ntags: [#a]\n---\n") == ["a"])
    }
}
