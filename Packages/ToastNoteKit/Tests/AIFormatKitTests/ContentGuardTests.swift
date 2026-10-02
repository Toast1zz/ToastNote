import Foundation
import Testing
@testable import AIFormatKit

@Suite struct ContentGuardTests {
    @Test func identicalPasses() {
        let text = "# 标题\n\n正文内容，包含一些文字。"
        #expect(ContentGuard.check(original: text, formatted: text).passed)
    }

    @Test func structureOnlyPasses() {
        let original = "周报\n本周完成重构。\n计划\n1 上线\n2 修复"
        let formatted = "# 周报\n\n本周完成重构。\n\n## 计划\n\n- 上线\n- 修复"
        let result = ContentGuard.check(original: original, formatted: formatted)
        #expect(result.passed)
        #expect(result.changedSentences.isEmpty)
    }

    @Test func orderedListNumbersMayBecomeListSyntax() {
        let original = "步骤\n1. 打开设置\n2. 选择账号\n3. 点击退出"
        let formatted = "## 步骤\n\n1. 打开设置\n2. 选择账号\n3. 点击退出"
        #expect(ContentGuard.check(original: original, formatted: formatted).passed)
    }

    @Test func punctuationTweakPasses() {
        #expect(ContentGuard.check(original: "a,b", formatted: "a，b").passed)
    }

    @Test func addedWordsFail() {
        let result = ContentGuard.check(original: "上线引导", formatted: "上线新手引导")
        #expect(!result.passed)
        #expect(result.changedSentences.contains { $0.contains("新手") })
    }

    @Test func deletedSentenceFails() {
        let original = "第一句话在这里。第二句话也在这里。第三句话同样在这里。"
        let formatted = "第一句话在这里。第三句话同样在这里。"
        let result = ContentGuard.check(original: original, formatted: formatted)
        #expect(!result.passed)
        #expect(result.changedSentences.contains { $0.contains("第二句话") })
    }

    @Test func sentencesDoNotBreakInsideIdentifiers() {
        // The change is after the "." of an identifier; the reported sentence must still start before it.
        let original = "之后调用 AuthService.login() 完成了登录。"
        let formatted = "之后调用 AuthService.login() 做完了登录。"
        let result = ContentGuard.check(original: original, formatted: formatted)
        #expect(!result.passed)
        #expect(result.changedSentences.contains { $0.contains("AuthService.login()") })
    }

    @Test func rewordFails() {
        #expect(!ContentGuard.check(original: "我觉得不错", formatted: "我认为很好").passed)
    }

    @Test func lengthGateShortCircuits() {
        let original = String(repeating: "字", count: 1000)
        let formatted = String(repeating: "字", count: 800)
        let clock = ContinuousClock()
        var result = GuardResult(passed: true, changedSentences: [])
        let elapsed = clock.measure { result = ContentGuard.check(original: original, formatted: formatted) }
        #expect(!result.passed)
        #expect(elapsed < .milliseconds(50))
    }

    @Test func englishCaseInsensitive() {
        #expect(ContentGuard.check(original: "Hello", formatted: "hello").passed)
    }

    @Test func markdownSyntaxIsNotText() {
        let original = "粗体 斜体 链接文字 代码"
        let formatted = "**粗体** *斜体* [链接文字](https://a.b) `代码`"
        #expect(ContentGuard.check(original: original, formatted: formatted).passed)
    }

    @Test func tableBecomesCells() {
        let original = "名称 数量\n苹果 3\n香蕉 5"
        let formatted = "| 名称 | 数量 |\n|---|---|\n| 苹果 | 3 |\n| 香蕉 | 5 |"
        #expect(ContentGuard.check(original: original, formatted: formatted).passed)
    }

    @Test func smallEditInALongTextIsToleratedButNotALargeOne() {
        let base = String(repeating: "这是一句用来测试的长文本。", count: 40)
        let oneCharChange = base.replacingOccurrences(of: "测试", with: "测验", range: base.range(of: "测试"))
        #expect(ContentGuard.check(original: base, formatted: oneCharChange).passed)
        let big = base.replacingOccurrences(of: "这是一句用来测试的长文本。", with: "完全不同的另一句话在这里。", options: [], range: base.startIndex..<base.index(base.startIndex, offsetBy: 120))
        #expect(!ContentGuard.check(original: base, formatted: big).passed)
    }

    @Test func emojiAndMixedScriptsDoNotCrash() {
        let result = ContentGuard.check(original: "😀 你好 world", formatted: "😀 你好 world")
        #expect(result.passed)
    }
}
