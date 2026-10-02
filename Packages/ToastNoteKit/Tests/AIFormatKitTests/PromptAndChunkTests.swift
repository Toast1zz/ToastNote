import Foundation
import Testing
@testable import AIFormatKit

/// Deterministic pseudo-random text so the property-style tests are reproducible.
private struct SeededGenerator {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}

private func generatedText(seed: UInt64, paragraphs: Int) -> String {
    var generator = SeededGenerator(state: seed)
    let pieces = ["这是一段中文内容，用来测试拆分。", "English sentence number one.", "## 小节标题", "⟦TN:0⟧ 占位符在这里", "- 列表项", "短"]
    var text = ""
    for _ in 0..<paragraphs {
        var paragraph = ""
        for _ in 0..<(1 + generator.next(40)) { paragraph += pieces[generator.next(pieces.count)] }
        text += paragraph + String(repeating: "\n", count: 1 + generator.next(3) * 1 + 1)
    }
    return text
}

@Suite struct PromptBuilderTests {
    @Test func systemPromptMentionsPlaceholder() {
        let prompt = PromptBuilder.system(extra: "", isFragment: false)
        #expect(prompt.contains("⟦TN:"))
    }

    @Test func systemPromptStatesTheFiveRules() {
        let prompt = PromptBuilder.system(extra: "", isFragment: false)
        #expect(prompt.contains("Markdown formatting assistant"))
        #expect(prompt.contains("Never add, delete, reword or translate any text"))
        #expect(prompt.lowercased().contains("placeholders"))
        #expect(prompt.contains("Do not add headings"))
        #expect(prompt.contains("Output only the formatted Markdown"))
    }

    @Test func extraAppended() {
        let prompt = PromptBuilder.system(extra: "列表一律用 -", isFragment: false)
        #expect(prompt.hasSuffix("Additional user requirements:\n列表一律用 -"))
    }

    @Test func emptyExtraAddsNothing() {
        #expect(!PromptBuilder.system(extra: "  \n ", isFragment: false).contains("Additional user requirements"))
    }

    @Test func fragmentSentence() {
        let prompt = PromptBuilder.system(extra: "", isFragment: true)
        #expect(prompt.contains("This is a fragment of a larger document. Do not add a document-level title."))
        #expect(!PromptBuilder.system(extra: "", isFragment: false).contains("fragment of a larger document"))
    }
}

@Suite struct ChunkerTests {
    @Test func shortTextSingleChunk() {
        #expect(Chunker.split("一段短文本。", limit: 6000) == ["一段短文本。"])
        #expect(Chunker.split("", limit: 6000) == [""])
    }

    @Test func splitsAtHeadingBoundary() {
        let first = String(repeating: "甲", count: 60) + "\n\n" + String(repeating: "乙", count: 30) + "\n\n"
        let second = "## 新章节\n\n" + String(repeating: "丙", count: 40)
        let parts = Chunker.split(first + second, limit: 120)
        #expect(parts.count == 2)
        #expect(parts[1].hasPrefix("## 新章节"))
    }

    @Test func splitsOnlyAtBlankLines() {
        let text = (0..<30).map { "第 \($0) 段，" + String(repeating: "字", count: 50) }.joined(separator: "\n\n")
        for part in Chunker.split(text, limit: 300) {
            #expect(!part.hasPrefix("\n") || part.hasPrefix("\n\n") == false)
        }
        let parts = Chunker.split(text, limit: 300)
        #expect(parts.count > 1)
        // Every part after the first starts at the beginning of a paragraph.
        for part in parts.dropFirst() { #expect(part.hasPrefix("第 ")) }
    }

    @Test func aSingleHugeParagraphIsNeverCut() {
        let text = String(repeating: "长", count: 1000)
        #expect(Chunker.split(text, limit: 100) == [text])
    }

    @Test func partsStayNearTheLimit() {
        let text = (0..<200).map { _ in String(repeating: "字", count: 40) }.joined(separator: "\n\n")
        let parts = Chunker.split(text, limit: 500)
        #expect(parts.allSatisfy { $0.utf16.count <= 500 + 42 })
    }

    @Test func joinIsInverse() {
        for seed in 1...20 {
            let text = generatedText(seed: UInt64(seed), paragraphs: 30)
            for limit in [200, 1000, 6000] {
                #expect(Chunker.join(Chunker.split(text, limit: limit)) == text, "seed \(seed) limit \(limit)")
            }
        }
    }

    @Test func neverSplitsInsidePlaceholder() {
        for seed in 21...30 {
            let text = generatedText(seed: UInt64(seed), paragraphs: 30)
            let parts = Chunker.split(text, limit: 300)
            for part in parts {
                let opens = part.components(separatedBy: "⟦").count
                let closes = part.components(separatedBy: "⟧").count
                #expect(opens == closes, "seed \(seed)")
            }
        }
    }

    @Test func thirteenThousandCharactersMakeAtLeastThreeChunks() {
        let text = (0..<270).map { _ in String(repeating: "字", count: 48) }.joined(separator: "\n\n")
        #expect(text.utf16.count > 13_000)
        #expect(Chunker.split(text).count >= 3)
    }
}

@Suite struct ResponseCleanerTests {
    @Test func stripsMarkdownFence() {
        #expect(ResponseCleaner.clean("```markdown\n# 标题\n\n正文\n```") == "# 标题\n\n正文")
        #expect(ResponseCleaner.clean("```md\n# 标题\n```") == "# 标题")
        #expect(ResponseCleaner.clean("```\n正文\n```") == "正文")
    }

    @Test func stripsSurroundingWhitespace() {
        #expect(ResponseCleaner.clean("\n\n  # 标题\n\n") == "# 标题")
    }

    @Test func leavesInnerFences() {
        let text = "正文\n\n```swift\nlet x\n```\n\n结尾"
        #expect(ResponseCleaner.clean(text) == text)
    }

    @Test func onlyOneOuterFenceIsRemoved() {
        #expect(ResponseCleaner.clean("```markdown\n```swift\nx\n```\n```") == "```swift\nx\n```")
    }

    @Test func unmatchedOpeningFenceIsKept() {
        #expect(ResponseCleaner.clean("```markdown\n# 标题") == "```markdown\n# 标题")
    }
}
