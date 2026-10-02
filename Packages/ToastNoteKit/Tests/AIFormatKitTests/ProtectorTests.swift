import Foundation
import Testing
@testable import AIFormatKit

@Suite struct ProtectorTests {
    @Test func protectsCodeFence() {
        let protected = Protector.protect("前文\n\n```swift\nlet x = 1\n```\n\n后文")
        #expect(protected.text == "前文\n\n⟦TN:0⟧\n\n后文")
        #expect(protected.slots == ["```swift\nlet x = 1\n```"])
    }

    @Test func protectsInlineCode() {
        let protected = Protector.protect("调用 `foo()` 即可")
        #expect(protected.text == "调用 ⟦TN:0⟧ 即可")
        #expect(protected.slots == ["`foo()`"])
    }

    @Test func protectsLinkURLKeepsText() {
        let protected = Protector.protect("[文字](https://a.b/c)")
        #expect(protected.text == "[文字](⟦TN:0⟧)")
        #expect(protected.slots == ["https://a.b/c"])
    }

    @Test func protectsImageWhole() {
        let protected = Protector.protect("![截图](attachments/a.png)")
        #expect(protected.text == "⟦TN:0⟧")
        #expect(protected.slots == ["![截图](attachments/a.png)"])
    }

    @Test func protectsBareURL() {
        let protected = Protector.protect("见 https://example.org/x 这里")
        #expect(protected.text == "见 ⟦TN:0⟧ 这里")
        #expect(protected.slots == ["https://example.org/x"])
    }

    @Test func protectsFrontmatter() {
        let protected = Protector.protect("---\ntags: [a]\n---\n正文")
        #expect(protected.text == "⟦TN:0⟧\n正文")
        #expect(protected.slots == ["---\ntags: [a]\n---"])
    }

    @Test func numbersSlotsInDocumentOrder() {
        let protected = Protector.protect("`a` 和 `b` 与 https://x.y")
        #expect(protected.text == "⟦TN:0⟧ 和 ⟦TN:1⟧ 与 ⟦TN:2⟧")
    }

    @Test func plainTextIsUntouched() {
        let protected = Protector.protect("只有普通文字，没有需要保护的内容。")
        #expect(protected.text == "只有普通文字，没有需要保护的内容。")
        #expect(protected.slots.isEmpty)
    }

    @Test func codeInsideACodeBlockIsNotProtectedTwice() {
        let protected = Protector.protect("```\n`x` https://a.b\n```")
        #expect(protected.slots.count == 1)
    }

    @Test func offsetsAfterEmojiAndCJKAreCorrect() {
        let protected = Protector.protect("😀 中文 `code` 😀 [链接](https://a.b)")
        #expect(protected.slots == ["`code`", "https://a.b"])
        #expect(protected.text == "😀 中文 ⟦TN:0⟧ 😀 [链接](⟦TN:1⟧)")
    }

    @Test func roundTripIdentity() throws {
        let fixture = """
        ---
        tags: [测试, 工作/周报]
        ---
        # 标题

        正文有 `inline`、[链接](https://a.b/c?d=1) 和 https://example.org 以及 ![图](a/b.png)。

        ```swift
        let x = 1 // `not inline`
        ```

        - 列表项 `code`
        > 引用 [x](https://q.r)
        """
        let protected = Protector.protect(fixture)
        #expect(protected.text != fixture)
        #expect(try Protector.restore(protected.text, slots: protected.slots) == fixture)
    }

    @Test func missingSlotThrows() {
        let protected = Protector.protect("`a` 和 `b`")
        let damaged = protected.text.replacingOccurrences(of: "⟦TN:1⟧", with: "")
        #expect(throws: AIError.incompleteResult) { try Protector.restore(damaged, slots: protected.slots) }
    }

    @Test func duplicatedSlotThrows() {
        let protected = Protector.protect("`a` 和 `b`")
        let damaged = protected.text + " ⟦TN:0⟧"
        #expect(throws: AIError.incompleteResult) { try Protector.restore(damaged, slots: protected.slots) }
    }

    @Test func unknownSlotThrows() {
        let protected = Protector.protect("`a`")
        #expect(throws: AIError.incompleteResult) { try Protector.restore("⟦TN:0⟧ ⟦TN:7⟧", slots: protected.slots) }
    }

    @Test func reorderedSlotsAreRestoredToTheirContent() throws {
        let protected = Protector.protect("`a` 和 `b`")
        let reordered = "⟦TN:1⟧ 和 ⟦TN:0⟧"
        #expect(try Protector.restore(reordered, slots: protected.slots) == "`b` 和 `a`")
    }
}
