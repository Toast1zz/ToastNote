import Foundation
import Testing
@testable import EditorKit

private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

/// Runs the styler with the caret at `caret` (nil = no active block).
private func style(_ text: String, caret: Int? = nil, concealAll: Bool = false) -> StyleResult {
    let blocks = BlockParser.parse(text)
    let active = caret.map { blocks.indices(intersecting: NSRange(location: $0, length: 0)) } ?? IndexSet()
    return MarkdownStyler.style(blocks: blocks, text: text as NSString, active: active, concealAll: concealAll)
}

private extension StyleResult {
    func run(_ range: NSRange, role: TextStyle.Role) -> StyleRun? {
        runs.first { $0.range == range && $0.style.role == role }
    }
}

struct StylerCase: Sendable, CustomTestStringConvertible {
    let name: String
    let text: String
    let caret: Int?
    let hidden: [NSRange]
    let runs: [(NSRange, TextStyle.Role)]
    var testDescription: String { name }

    static let all: [StylerCase] = [
        .init(name: "heading inactive", text: "## 标题", caret: nil,
              hidden: [r(0, 3)], runs: [(r(3, 2), .heading(2))]),
        .init(name: "heading active", text: "## 标题", caret: 4,
              hidden: [], runs: [(r(0, 3), .marker), (r(3, 2), .heading(2))]),
        .init(name: "strong inactive", text: "**粗**", caret: nil,
              hidden: [r(0, 2), r(3, 2)], runs: [(r(2, 1), .body)]),
        .init(name: "strong active", text: "**粗**", caret: 3,
              hidden: [], runs: [(r(0, 2), .marker), (r(3, 2), .marker)]),
        .init(name: "inline code inactive", text: "`c`", caret: nil,
              hidden: [r(0, 1), r(2, 1)], runs: [(r(1, 1), .codeInline)]),
        .init(name: "link inactive", text: "[文字](https://x.y)", caret: nil,
              hidden: [r(0, 1), r(3, 14)], runs: [(r(1, 2), .link)]),
        .init(name: "link active", text: "[文字](https://x.y)", caret: 2,
              hidden: [], runs: [(r(0, 1), .marker), (r(1, 2), .link), (r(3, 14), .marker)]),
        .init(name: "bare url", text: "见 https://a.b", caret: nil,
              hidden: [], runs: [(r(2, 11), .link)]),
        .init(name: "task done inactive", text: "- [x] 完成", caret: nil,
              hidden: [r(0, 6)], runs: [(r(6, 2), .taskDone)]),
        .init(name: "task open inactive", text: "- [ ] 待办", caret: nil,
              hidden: [r(0, 6)], runs: [(r(6, 2), .body)]),
        .init(name: "bullet inactive", text: "- 项", caret: nil,
              hidden: [r(0, 2)], runs: [(r(2, 1), .body)]),
        .init(name: "bullet active", text: "- 项", caret: 2,
              hidden: [], runs: [(r(0, 2), .marker)]),
        .init(name: "ordered keeps number", text: "1. 项", caret: nil,
              hidden: [], runs: [(r(0, 3), .marker), (r(3, 1), .body)]),
        .init(name: "quote inactive", text: "> 引用", caret: nil,
              hidden: [r(0, 2)], runs: [(r(2, 2), .quote)]),
        .init(name: "fence inactive", text: "```swift\nlet x\n```", caret: nil,
              hidden: [r(0, 8), r(15, 3)], runs: [(r(9, 5), .codeBlock)]),
        .init(name: "fence active", text: "```swift\nlet x\n```", caret: 10,
              hidden: [], runs: [(r(0, 8), .marker), (r(15, 3), .marker), (r(9, 5), .codeBlock)]),
        .init(name: "rule inactive", text: "a\n\n---", caret: 0,
              hidden: [r(3, 3)], runs: []),
        .init(name: "tag", text: "看 #工作", caret: nil,
              hidden: [], runs: [(r(2, 3), .tag)]),
    ]
}

@Suite struct MarkdownStylerTests {
    @Test(arguments: StylerCase.all)
    func styles(_ c: StylerCase) {
        let result = style(c.text, caret: c.caret)
        #expect(result.hidden.sorted { $0.location < $1.location } == c.hidden, "hidden")
        for (range, role) in c.runs {
            #expect(result.run(range, role: role) != nil, "run \(range) \(role)")
        }
    }

    @Test func strongRunIsBold() {
        let result = style("**粗**")
        #expect(result.run(r(2, 1), role: .body)?.style.bold == true)
    }

    @Test func emphasisRunIsItalicAndNestedStrongCombines() {
        let result = style("***x***")
        let inner = result.runs.last { $0.range == r(3, 1) }
        #expect(inner?.style.bold == true)
        #expect(inner?.style.italic == true)
    }

    @Test func boldInsideHeadingKeepsHeadingRole() {
        let result = style("# a **b**")
        #expect(result.runs.contains { $0.style.role == .heading(1) && $0.style.bold && $0.range == r(6, 1) })
    }

    @Test func blockStyleCoversMarkersSoParagraphAttributesApply() {
        // A paragraph's spacing comes from its first character, which for headings is a (hidden) marker.
        let result = style("## 标题")
        #expect(result.run(r(0, 5), role: .heading(2)) != nil)
    }

    @Test func bulletItemsReserveAGutterButOrderedItemsDoNot() {
        #expect(style("- 项").runs.contains { $0.range == r(0, 3) && $0.style.listIndent })
        #expect(!style("1. 项").runs.contains { $0.style.listIndent })
    }

    @Test func bulletDecoration() {
        #expect(style("- 项").decorations.contains(.bullet(at: 0, depth: 0)))
    }

    @Test func checkboxDecoration() {
        #expect(style("- [x] 完成").decorations.contains(.checkbox(at: 0, done: true)))
        #expect(style("- [ ] 待办").decorations.contains(.checkbox(at: 0, done: false)))
    }

    @Test func quoteBarAndCodeBackgroundAndLanguage() {
        #expect(style("> 引用").decorations.contains(.quoteBar(r(0, 4))))
        let code = style("```swift\nlet x\n```").decorations
        #expect(code.contains(.codeBackground(r(0, 18))))
        #expect(code.contains(.codeLanguage("swift", r(0, 18))))
    }

    @Test func ruleDecorationOnlyWhenInactive() {
        #expect(style("a\n\n---").decorations.contains(.rule(r(3, 3))))
        #expect(!style("a\n\n---", caret: 4).decorations.contains(.rule(r(3, 3))))
    }

    @Test func tagPillAndInlineCodeBackground() {
        #expect(style("看 #工作").decorations.contains(.tagPill(r(2, 3))))
        #expect(style("`c`").decorations.contains(.inlineCodeBackground(r(1, 1))))
    }

    @Test func imageInactiveHidesLineAndAddsDecoration() {
        let result = style("![图](a.png)")
        #expect(result.hidden == [r(0, 11)])
        #expect(result.decorations.contains(.image(source: "a.png", lineRange: r(0, 11))))
    }

    @Test func tableIsMonospaceWithMutedPipes() {
        let result = style("| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(result.hidden.isEmpty)
        #expect(result.runs.contains { $0.style.role == .codeInline && $0.range == r(0, 29) })
        #expect(result.runs.contains { $0.style.role == .marker && $0.range == r(0, 1) })
        #expect(result.runs.contains { $0.style.role == .marker && $0.range == r(10, 9) })  // separator row
    }

    @Test func frontmatterInactiveCollapsesToSummary() {
        let result = style("---\ntags: [a]\ntitle: x\n---\n正文", caret: 27)
        #expect(result.hidden == [r(0, 26)])
        #expect(result.decorations.contains(.frontmatterSummary(count: 2, lineRange: r(0, 3))))
    }

    @Test func frontmatterActiveShowsEverything() {
        let result = style("---\ntags: [a]\ntitle: x\n---\n正文", caret: 5)
        #expect(result.hidden.isEmpty)
        #expect(!result.decorations.contains { if case .frontmatterSummary = $0 { true } else { false } })
    }

    @Test func concealAllHidesEverything() {
        let text = "## 标题\n\n**粗** [a](https://b.c)"
        let blocks = BlockParser.parse(text)
        let all = IndexSet(0..<blocks.count)
        let concealed = MarkdownStyler.style(blocks: blocks, text: text as NSString, active: all, concealAll: true)
        let inactive = MarkdownStyler.style(blocks: blocks, text: text as NSString, active: IndexSet(), concealAll: false)
        #expect(concealed == inactive)
    }
}
