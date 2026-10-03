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
        .init(name: "ordered inactive draws its number in the gutter", text: "1. 项", caret: nil,
              hidden: [r(0, 3)], runs: [(r(3, 1), .body)]),
        .init(name: "ordered active", text: "1. 项", caret: 3,
              hidden: [], runs: [(r(0, 3), .marker)]),
        .init(name: "quote inactive", text: "> 引用", caret: nil,
              hidden: [r(0, 2)], runs: [(r(2, 2), .quote)]),
        .init(name: "fence inactive", text: "```swift\nlet x\n```", caret: nil,
              hidden: [r(0, 9), r(14, 4)], runs: [(r(9, 5), .codeBlock)]),
        .init(name: "fence active", text: "```swift\nlet x\n```", caret: 10,
              hidden: [], runs: [(r(0, 8), .marker), (r(15, 3), .marker), (r(9, 5), .codeBlock)]),
        .init(name: "rule inactive keeps one stand-in character", text: "a\n\n---", caret: 0,
              hidden: [r(4, 2)], runs: [(r(3, 1), .rulePlaceholder)]),
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

    @Test func lineHeightIsAMultipleOfTheFontSizeNotOfTheNaturalLineHeight() {
        // Spec §9.3: body 1.75, headings 1.35, code 1.5 times the font size.
        let theme = EditorTheme.default
        let body = theme.paragraphStyle(for: TextStyle(role: .body))
        #expect(body.minimumLineHeight == 1.75 * 15 && body.maximumLineHeight == 1.75 * 15)
        let heading = theme.paragraphStyle(for: TextStyle(role: .heading(1)))
        #expect(heading.minimumLineHeight == 1.35 * 28)
        let code = theme.paragraphStyle(for: TextStyle(role: .codeBlock))
        #expect(code.maximumLineHeight == 1.5 * 13)
    }

    @Test func blockStyleCoversMarkersSoParagraphAttributesApply() {
        // A paragraph's spacing comes from its first character, which for headings is a (hidden) marker.
        let result = style("## 标题")
        #expect(result.run(r(0, 5), role: .heading(2)) != nil)
    }

    @Test func blankLinesBetweenBlocksAreCompact() {
        // Blank lines are real empty paragraphs; left alone they would double every paragraph gap.
        let result = style("a\n\n\nb")
        let blanks = result.runs.filter { $0.style.blankLine != nil }.map(\.range)
        #expect(blanks == [r(2, 1), r(3, 1)])
    }

    @Test func blankLineRemembersWhatFollowsIt() {
        // A hidden "## " rides on the previous line fragment, so the blank line in front carries the heading gap.
        let heading = style("a\n\n## b").runs.first { $0.style.blankLine != nil }
        #expect(heading?.style.blankLine == .beforeHeading(2))
        let code = style("a\n\n```\nx\n```").runs.first { $0.style.blankLine != nil }
        #expect(code?.style.blankLine == .besideBox)
        let afterCode = style("```\nx\n```\n\nb").runs.first { $0.style.blankLine != nil }
        #expect(afterCode?.style.blankLine == .besideBox)
        let beforeTable = style("a\n\n| a |\n|---|").runs.first { $0.style.blankLine != nil }
        #expect(beforeTable?.style.blankLine == .besideBox)
        let headingAfterCode = style("```\nx\n```\n\n## h").runs.first { $0.style.blankLine != nil }
        #expect(headingAfterCode?.style.blankLine == .beforeHeading(2, afterBox: true))
        let plain = style("a\n\nb").runs.first { $0.style.blankLine != nil }
        #expect(plain?.style.blankLine == .plain)
    }

    @Test func blankLineHeightGrowsBeforeHeadings() {
        let theme = EditorTheme.default
        let plain = theme.paragraphStyle(for: TextStyle(role: .body, blankLine: .plain))
        let heading = theme.paragraphStyle(for: TextStyle(role: .body, blankLine: .beforeHeading(2)))
        #expect(plain.maximumLineHeight == 0.5 * 15)
        #expect(heading.maximumLineHeight == 1.1 * 22)
    }

    @Test func noBlankRunsBetweenListItemsOrAfterNestedMarkers() {
        #expect(style("- a\n- b\n  - c").runs.allSatisfy { $0.style.blankLine == nil })
    }

    @Test func listItemsUseTightSpacing() {
        #expect(style("1. 一\n2. 二").runs.contains { $0.style.tightSpacing })
        #expect(!style("段落").runs.contains { $0.style.tightSpacing })
    }

    @Test func nestedBulletHidesSourceIndentAndIndentsByDepth() {
        let text = "- a\n  - b"
        let result = style(text)
        #expect(result.hidden.contains(r(4, 2)))                  // the two source spaces
        #expect(result.runs.contains { $0.range == r(4, 5) && $0.style.listDepth == 1 })
        // The caret inside the item shows the source indentation and marker, which hang in the gutter.
        let active = style(text, caret: 7)
        #expect(!active.hidden.contains(r(4, 2)))
        #expect(active.runs.contains { $0.range == r(4, 5) && $0.style.listDepth == 1 && $0.style.hangingPrefix == "  - " })
    }

    @Test func listItemsReserveAGutter() {
        #expect(style("- 项").runs.contains { $0.range == r(0, 3) && $0.style.listDepth == 0 })
        #expect(style("1. 项").runs.contains { $0.range == r(0, 4) && $0.style.listDepth == 0 })
    }

    @Test func orderedNumberDecorationAndNesting() {
        #expect(style("1. 项").decorations.contains(.orderedNumber("1.", at: 0, depth: 0)))
        #expect(!style("1. 项", caret: 3).decorations.contains { if case .orderedNumber = $0 { true } else { false } })
        let nested = style("1. a\n   1) b")
        #expect(nested.hidden.contains(r(5, 3)))  // source indentation
        #expect(nested.decorations.contains(.orderedNumber("1)", at: 8, depth: 1)))
        #expect(nested.runs.contains { $0.range == r(5, 7) && $0.style.listDepth == 1 })
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
        #expect(result.hidden == [r(1, 10)])  // "!" stays as an invisible stand-in so the line exists
        #expect(result.decorations.contains(.image(source: "a.png", lineRange: r(0, 11))))
    }

    @Test func inactiveTableBecomesAGrid() {
        let result = style("| a | b |\n|---|---|\n| 1 | 2 |")
        // Cell padding, the closing pipe and the delimiter row (with its line break) are hidden; inner pipes stay
        // as invisible spacers that the view widens to the column width. The opening pipe stays too (the view
        // cancels its width): leading hidden glyphs would move the row's text onto a continuation line.
        #expect(result.hidden.sorted { $0.location < $1.location } == [
            r(1, 1), r(3, 1), r(5, 1), r(7, 2), r(10, 10), r(21, 1), r(23, 1), r(25, 1), r(27, 2),
        ])
        let layout = TableLayout(range: r(0, 29), rows: [
            TableRow(line: r(0, 9), cells: [r(2, 1), r(6, 1)], spacers: [4], isHeader: true, leadingPipe: 0),
            TableRow(line: r(20, 9), cells: [r(22, 1), r(26, 1)], spacers: [24], isHeader: false, leadingPipe: 20),
        ])
        #expect(result.decorations.contains(.table(layout)))
        #expect(result.runs.contains { $0.range == r(2, 1) && $0.style.bold })
        #expect(result.runs.contains { $0.range == r(26, 1) && !$0.style.bold && $0.style.role == .body })
        #expect(result.runs.contains { $0.range == r(4, 1) && $0.style.role == .tableSpacer })
        #expect(result.runs.contains { $0.range == r(0, 29) && $0.style.tableRow })
    }

    @Test func tableRowsWithoutOuterPipesAndEscapedPipes() {
        let result = style("a | b\\|c\n--|--")
        let table = result.decorations.compactMap { if case .table(let layout) = $0 { layout } else { nil } }.first
        #expect(table?.rows.first?.cells == [r(0, 1), r(4, 4)])
        #expect(table?.rows.first?.spacers == [2])
    }

    @Test func activeTableIsMonospaceWithMutedPipes() {
        let result = style("| a | b |\n|---|---|\n| 1 | 2 |", caret: 1)
        #expect(result.hidden.isEmpty)
        #expect(result.runs.contains { $0.style.role == .codeInline && $0.range == r(0, 29) })
        #expect(result.runs.contains { $0.style.role == .marker && $0.range == r(0, 1) })
        #expect(result.runs.contains { $0.style.role == .marker && $0.range == r(10, 9) })  // separator row
    }

    @Test func frontmatterInactiveCollapsesToSummary() {
        let result = style("---\ntags: [a]\ntitle: x\n---\n正文", caret: 27)
        #expect(result.hidden == [r(1, 25)])  // the first "-" stays as the summary line's stand-in
        #expect(result.runs.contains { $0.range == r(0, 1) && $0.style.role == .frontmatterPlaceholder })
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
