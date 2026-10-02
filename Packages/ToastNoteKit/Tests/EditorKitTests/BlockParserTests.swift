import Foundation
import Testing
@testable import EditorKit

private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

@Suite struct BlockParserTests {
    @Test func heading() {
        let blocks = BlockParser.parse("## 标题")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .heading(level: 2))
        #expect(blocks[0].range == r(0, 5))
        #expect(blocks[0].syntaxRanges == [r(0, 3)])
        #expect(blocks[0].contentRange == r(3, 2))
    }

    @Test func paragraphsAreSeparateBlocks() {
        let blocks = BlockParser.parse("第一段\n\n第二段")
        #expect(blocks.map(\.kind) == [.paragraph, .paragraph])
        #expect(blocks[1].range == r(5, 3))
    }

    @Test func strongInline() {
        let inline = BlockParser.parse("a **b** c")[0].inlines
        #expect(inline.count == 1)
        #expect(inline[0].kind == .strong)
        #expect(inline[0].range == r(2, 5))
        #expect(inline[0].syntaxRanges == [r(2, 2), r(5, 2)])
    }

    @Test func emphasisAndStrikethroughAndCode() {
        let inlines = BlockParser.parse("*a* ~~b~~ `c`")[0].inlines
        #expect(inlines.map(\.kind) == [.emphasis, .strikethrough, .inlineCode])
        #expect(inlines[0].syntaxRanges == [r(0, 1), r(2, 1)])
        #expect(inlines[1].syntaxRanges == [r(4, 2), r(7, 2)])
        #expect(inlines[2].syntaxRanges == [r(10, 1), r(12, 1)])
    }

    @Test func nestedStrongInEmphasisGetsDistinctRanges() {
        // cmark-gfm reports the same range for both; the inner span must start after the outer markers.
        let inlines = BlockParser.parse("***x***")[0].inlines
        let strong = inlines.first { $0.kind == .strong }
        #expect(strong?.range == r(1, 5))
        #expect(strong?.syntaxRanges == [r(1, 2), r(4, 2)])
    }

    @Test func link() {
        let inline = BlockParser.parse("[文字](https://x.y)")[0].inlines
        #expect(inline.count == 1)
        #expect(inline[0].kind == .link(url: "https://x.y"))
        #expect(inline[0].syntaxRanges == [r(0, 1), r(3, 14)])
    }

    @Test func image() {
        let inline = BlockParser.parse("![图](a/b.png)")[0].inlines
        #expect(inline.count == 1)
        #expect(inline[0].kind == .image(source: "a/b.png"))
    }

    @Test func taskItems() {
        let blocks = BlockParser.parse("- [ ] a\n- [x] b")
        #expect(blocks.map(\.kind) == [
            .listItem(ordered: false, task: .open, depth: 0),
            .listItem(ordered: false, task: .done, depth: 0),
        ])
        #expect(blocks[0].syntaxRanges == [r(0, 6)])
        #expect(blocks[0].contentRange == r(6, 1))
        #expect(blocks[1].range == r(8, 7))
    }

    @Test func plainBulletsAndOrdered() {
        let blocks = BlockParser.parse("- 项\n\n1. 一\n2. 二")
        #expect(blocks[0].kind == .listItem(ordered: false, task: nil, depth: 0))
        #expect(blocks[0].syntaxRanges == [r(0, 2)])
        #expect(blocks[1].kind == .listItem(ordered: true, task: nil, depth: 0))
        #expect(blocks[1].syntaxRanges == [r(5, 3)])
        #expect(blocks.count == 3)
    }

    @Test func nestedList() {
        let blocks = BlockParser.parse("- a\n  - b")
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .listItem(ordered: false, task: nil, depth: 0))
        #expect(blocks[0].range == r(0, 3))
        #expect(blocks[1].kind == .listItem(ordered: false, task: nil, depth: 1))
        #expect(blocks[1].range == r(6, 3))
    }

    @Test func quote() {
        let blocks = BlockParser.parse("> 引用\n> 第二行")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .quote)
        #expect(blocks[0].syntaxRanges == [r(0, 2), r(5, 2)])
    }

    @Test func codeFence() {
        let blocks = BlockParser.parse("```swift\nlet x\n```")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .codeBlock(language: "swift"))
        #expect(blocks[0].range == r(0, 18))
        #expect(blocks[0].syntaxRanges == [r(0, 8), r(15, 3)])
        #expect(blocks[0].contentRange == r(9, 5))
    }

    @Test func thematicBreak() {
        let blocks = BlockParser.parse("a\n\n---\n\nb")
        #expect(blocks[1].kind == .thematicBreak)
        #expect(blocks[1].syntaxRanges == [r(3, 3)])
    }

    @Test func table() {
        let blocks = BlockParser.parse("| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .table)
    }

    @Test func frontmatter() {
        let blocks = BlockParser.parse("---\ntags: [a]\n---\n正文")
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .frontmatter)
        #expect(blocks[0].range == r(0, 17))
        #expect(blocks[0].syntaxRanges == [r(0, 17)])
        #expect(blocks[1].kind == .paragraph)
        #expect(blocks[1].range == r(18, 2))
    }

    @Test func tagsAndBareURLs() {
        let inlines = BlockParser.parse("看 #工作/周报 和 https://a.b")[0].inlines
        #expect(inlines.contains { $0.kind == .tag("工作/周报") && $0.range == r(2, 6) })
        #expect(inlines.contains { $0.kind == .bareURL("https://a.b") })
    }

    @Test func hashInCodeIsNotTag() {
        let inlines = BlockParser.parse("`#x`")[0].inlines
        #expect(!inlines.contains { if case .tag = $0.kind { true } else { false } })
    }

    @Test func numericHashIsNotTag() {
        let inlines = BlockParser.parse("#123")[0].inlines
        #expect(inlines.isEmpty)
    }

    @Test func hashInLinkTextIsNotTag() {
        let inlines = BlockParser.parse("[#x](https://a.b)")[0].inlines
        #expect(!inlines.contains { if case .tag = $0.kind { true } else { false } })
    }

    @Test func tagInHeadingAndListItem() {
        #expect(BlockParser.parse("# 标题 #t")[0].inlines.contains { $0.kind == .tag("t") })
        #expect(BlockParser.parse("- 事项 #t")[0].inlines.contains { $0.kind == .tag("t") })
    }

    @Test func rangesAfterEmojiAndCJKAreUTF16() {
        let text = "😀 中文\n\n**粗**"
        let blocks = BlockParser.parse(text)
        let ns = text as NSString
        #expect(ns.substring(with: blocks[1].range) == "**粗**")
        #expect(ns.substring(with: blocks[1].inlines[0].range) == "**粗**")
        #expect(ns.substring(with: blocks[1].inlines[0].syntaxRanges[0]) == "**")
    }

    @Test func blocksAreSortedAndEmptyTextIsEmpty() {
        #expect(BlockParser.parse("").isEmpty)
        let blocks = BlockParser.parse("# a\n\n- b\n\n> c")
        #expect(blocks.map(\.range.location) == blocks.map(\.range.location).sorted())
    }

    @Test func indicesIntersecting() {
        let blocks = BlockParser.parse("# a\n\nbb\n\nccc")
        #expect(blocks.indices(intersecting: r(0, 0)) == IndexSet(integer: 0))
        #expect(blocks.indices(intersecting: r(3, 0)) == IndexSet(integer: 0))   // caret at block end
        #expect(blocks.indices(intersecting: r(4, 0)) == IndexSet())             // blank line between blocks
        #expect(blocks.indices(intersecting: r(0, 8)) == IndexSet([0, 1]))
    }
}
