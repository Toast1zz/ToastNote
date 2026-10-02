import Foundation
import Testing
@testable import AIFormatKit

@Suite struct BlockDiffTests {
    @Test func paragraphToHeading() {
        let result = BlockDiff.compare(original: "周报\n\n本周完成重构。", formatted: "# 周报\n\n本周完成重构。")
        #expect(result.changes == [0: .becameHeading])
    }

    @Test func paragraphToList() {
        // One paragraph with numbered lines becomes two list items: both are marked, as a list, not a split.
        let result = BlockDiff.compare(original: "1 a\n2 b", formatted: "- a\n- b")
        #expect(result.changes == [0: .becameList, 1: .becameList])
        #expect(result.alignments == [BlockAlignment(original: 0..<1, formatted: 0..<2)])
    }

    @Test func paragraphToQuoteAndTable() {
        #expect(BlockDiff.compare(original: "引用内容", formatted: "> 引用内容").changes == [0: .becameQuote])
        let table = BlockDiff.compare(original: "名称 数量\n\n苹果 3", formatted: "| 名称 | 数量 |\n|---|---|\n| 苹果 | 3 |")
        #expect(table.changes.values.contains(.becameTable))
    }

    @Test func splitParagraph() {
        let result = BlockDiff.compare(original: "第一句话。第二句话。", formatted: "第一句话。\n\n第二句话。")
        #expect(result.changes == [0: .split, 1: .split])
        #expect(result.alignments == [BlockAlignment(original: 0..<1, formatted: 0..<2)])
    }

    @Test func mergedParagraphs() {
        let result = BlockDiff.compare(original: "第一句话。\n\n第二句话。", formatted: "第一句话。第二句话。")
        #expect(result.changes == [0: .merged])
        #expect(result.alignments == [BlockAlignment(original: 0..<2, formatted: 0..<1)])
    }

    @Test func addedEmphasis() {
        let result = BlockDiff.compare(original: "重点内容在这里", formatted: "**重点内容**在这里")
        #expect(result.changes == [0: .addedEmphasis])
    }

    @Test func existingEmphasisIsNotNew() {
        let text = "**重点内容**在这里"
        #expect(BlockDiff.compare(original: text, formatted: text).changes.isEmpty)
    }

    @Test func unchangedDocumentHasNoChanges() {
        let text = "# 标题\n\n正文一。\n\n- 项一\n- 项二\n\n> 引用"
        let result = BlockDiff.compare(original: text, formatted: text)
        #expect(result.changes.isEmpty)
        #expect(result.alignments.count == 5)
    }

    @Test func alignmentsCoverAllBlocks() {
        let original = "标题行\n\n第一段。第二段。\n\n1 甲\n2 乙\n\n结尾。"
        let formatted = "# 标题行\n\n第一段。\n\n第二段。\n\n- 甲\n- 乙\n\n结尾。"
        let result = BlockDiff.compare(original: original, formatted: formatted)
        var originalSeen = Set<Int>()
        var formattedSeen = Set<Int>()
        for alignment in result.alignments {
            originalSeen.formUnion(alignment.original)
            formattedSeen.formUnion(alignment.formatted)
        }
        #expect(originalSeen == Set(0..<3 + 1))   // heading-like line, paragraph, numbered paragraph, closing
        #expect(formattedSeen == Set(0..<6))
        // Alignments are ordered and do not overlap.
        let starts = result.alignments.map(\.formatted.lowerBound)
        #expect(starts == starts.sorted())
    }

    @Test func differentTextStillAlignsWithoutHanging() {
        let result = BlockDiff.compare(original: "完全不同的内容\n\n第二段", formatted: "另一些文字\n\n第二段")
        #expect(!result.alignments.isEmpty)
    }

    @Test func labelsMatchTheSpec() {
        #expect(BlockChangeKind.becameHeading.label == "变为标题")
        #expect(BlockChangeKind.becameList.label == "变为列表")
        #expect(BlockChangeKind.becameQuote.label == "变为引用")
        #expect(BlockChangeKind.becameTable.label == "变为表格")
        #expect(BlockChangeKind.split.label == "拆分段落")
        #expect(BlockChangeKind.merged.label == "合并段落")
        #expect(BlockChangeKind.addedEmphasis.label == "新增强调")
    }
}
