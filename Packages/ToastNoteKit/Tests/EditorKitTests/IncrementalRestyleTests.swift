import AppKit
import Foundation
import Testing
@testable import EditorKit

@MainActor private var retainedWindows: [NSWindow] = []

@MainActor
private func makeView(_ text: String) -> MarkdownTextView {
    let view = MarkdownTextView(theme: .default)
    view.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = view
    retainedWindows.append(window)
    view.markdown = text
    return view
}

private let document = """
# 标题

第一段 **粗体** 和 `代码`。

- 项一
- [ ] 待办
  - 嵌套

> 引用

```swift
let x = 1
```

结尾段落 #标签
"""

/// Attribute of every character plus the hidden set; two views that look the same have equal snapshots.
@MainActor
private func snapshot(_ view: MarkdownTextView) -> [String] {
    let storage = view.textStorage!
    var lines: [String] = []
    for index in 0..<storage.length {
        let attributes = storage.attributes(at: index, effectiveRange: nil)
        // Compare size and traits, not the face name: AppKit swaps in PingFang for CJK runs on its own.
        let font = (attributes[.font] as? NSFont).map { "\($0.pointSize)/\($0.fontDescriptor.symbolicTraits.rawValue & 0b11) " + ($0.isFixedPitch ? "mono" : "prop") } ?? "-"
        let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
        let color = (attributes[.foregroundColor] as? NSColor)?.description ?? "-"
        let strike = attributes[.strikethroughStyle] as? Int ?? 0
        lines.append("\(index) \(font) \(color) \(strike) \(paragraph?.firstLineHeadIndent ?? -1) \(paragraph?.paragraphSpacing ?? -1) \(paragraph?.minimumLineHeight ?? -1)")
    }
    view.layoutManager?.ensureLayout(forCharacterRange: NSRange(location: 0, length: storage.length))
    for index in 0..<storage.length {
        let glyph = view.layoutManager!.glyphIndexForCharacter(at: index)
        lines.append("g\(index) \(view.layoutManager!.propertyForGlyph(at: glyph).contains(.null))")
    }
    return lines
}

@MainActor @Suite struct IncrementalRestyleTests {
    /// Types `insertion` at `location` into a view showing `document`, then compares with a view loaded with the result.
    private func expectSameAsFullRestyle(insert insertion: String, at location: Int, replacing length: Int = 0, caretAfter: Int? = nil) {
        let typed = makeView(document)
        typed.setSelectedRange(NSRange(location: location, length: 0))
        typed.insertText(insertion, replacementRange: NSRange(location: location, length: length))
        let final = typed.string
        let fresh = makeView(final)
        fresh.setSelectedRange(typed.selectedRange())
        #expect(typed.string == final)
        let (a, b) = (snapshot(typed), snapshot(fresh))
        let differences = zip(a, b).enumerated().filter { $0.element.0 != $0.element.1 }.prefix(4).map { "\($0.offset): typed [\($0.element.0)] fresh [\($0.element.1)]" }
        #expect(a == b, "inserting \(insertion.debugDescription) at \(location): \(differences.joined(separator: " | "))")
    }

    @Test func typingInAParagraph() {
        expectSameAsFullRestyle(insert: "新", at: 20)
    }

    @Test func typingInsideInlineMarkers() {
        expectSameAsFullRestyle(insert: "x", at: 15)
    }

    @Test func openingAFenceRestylesEverythingAfterIt() {
        expectSameAsFullRestyle(insert: "```\n", at: 0)
    }

    @Test func breakingAHeadingMarker() {
        expectSameAsFullRestyle(insert: "x", at: 1)
    }

    @Test func addingAListItem() {
        expectSameAsFullRestyle(insert: "\n- 新项", at: 30)
    }

    @Test func deletingAWholeBlock() {
        let blockStart = (document as NSString).range(of: "> 引用").location
        expectSameAsFullRestyle(insert: "", at: blockStart, replacing: 5)
    }

    @Test func typingAtTheEndOfTheDocument() {
        expectSameAsFullRestyle(insert: "尾", at: (document as NSString).length)
    }

    @Test func typingDoesNotRunAFullPass() {
        let view = makeView(document)
        view.setSelectedRange(NSRange(location: 20, length: 0))
        view.insertText("新", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.lastRestyledRange != nil)
        #expect(view.lastRestyledRange!.length < (view.string as NSString).length)
    }
}
