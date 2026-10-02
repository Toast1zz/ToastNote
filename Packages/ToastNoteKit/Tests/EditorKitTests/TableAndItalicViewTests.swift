import AppKit
import Foundation
import Testing
@testable import EditorKit

@MainActor
private var retainedWindows: [NSWindow] = []

@MainActor
private func makeView(_ text: String) -> MarkdownTextView {
    let view = MarkdownTextView(theme: .default)
    view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = view
    retainedWindows.append(window)
    view.markdown = text
    view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    view.layoutManager?.ensureLayout(for: view.textContainer!)
    return view
}

/// X position of the character at `index`, in container coordinates.
@MainActor
private func x(_ view: MarkdownTextView, _ index: Int) -> CGFloat {
    let layoutManager = view.layoutManager!
    let glyph = layoutManager.glyphIndexForCharacter(at: index)
    return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX + layoutManager.location(forGlyphAt: glyph).x
}

@MainActor @Suite struct TableAndItalicViewTests {
    @Test func tableColumnsLineUpAcrossRows() {
        // Row 0: "| a | b |", row 2: "| 一二三四 | 2 |"; the trailing paragraph keeps the caret out of the table.
        let text = "| a | b |\n|---|---|\n| 一二三四 | 2 |\n\n尾"
        let view = makeView(text)
        let bInHeader = 6
        let twoInBody = (text as NSString).range(of: "2 |").location
        #expect(abs(x(view, bInHeader) - x(view, twoInBody)) < 0.5)
        // The first column is as wide as its widest cell plus the gap.
        #expect(x(view, twoInBody) - x(view, 22) > 4 * 15)
    }

    @Test func aWrappedLastCellContinuesUnderItsOwnColumn() {
        let text = "| a | b |\n|---|---|\n| x | " + String(repeating: "很长的说明文字", count: 30) + " |\n\n尾"
        let view = makeView(text)
        let cell = (text as NSString).range(of: "很长").location
        let style = view.textStorage!.attribute(.paragraphStyle, at: cell, effectiveRange: nil) as? NSParagraphStyle
        let padding = view.textContainer!.lineFragmentPadding
        #expect(abs((style?.headIndent ?? 0) + padding - x(view, cell)) < 0.5)
    }

    @Test func tableColumnWidthsArePublishedForDrawing() {
        let view = makeView("| a | b |\n|---|---|\n| 1 | 2 |\n\n尾")
        #expect(view.tableColumnWidths[0]?.count == 2)
    }

    @Test func spaceAfterATagIsWidenedSoNeighbouringPillsDoNotTouch() {
        let view = makeView("#读书 #设计\n\n尾")
        let kern = view.textStorage!.attribute(.kern, at: 3, effectiveRange: nil) as? CGFloat
        #expect((kern ?? 0) >= 6)
    }

    @Test func cjkItalicIsSlantedButLatinUsesTheItalicFace() {
        let view = makeView("*中a*\n\n尾")
        let storage = view.textStorage!
        #expect(storage.attribute(.obliqueness, at: 1, effectiveRange: nil) as? CGFloat == 0.2)
        #expect(storage.attribute(.obliqueness, at: 2, effectiveRange: nil) == nil)
    }
}
