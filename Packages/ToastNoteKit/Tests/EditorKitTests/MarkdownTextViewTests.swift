import AppKit
import Foundation
import Testing
@testable import EditorKit

@MainActor
private var retainedWindows: [NSWindow] = []

/// The view lives in an off-screen window so it has the window's undo manager, like in the app.
@MainActor
private func makeView(_ text: String, concealAll: Bool = false) -> MarkdownTextView {
    let view = MarkdownTextView(theme: .default, concealAll: concealAll)
    view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = view
    retainedWindows.append(window)
    view.markdown = text
    return view
}

@MainActor
private func isHidden(_ view: MarkdownTextView, character: Int) -> Bool {
    guard let layoutManager = view.layoutManager else { return false }
    layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: (view.string as NSString).length))
    let glyph = layoutManager.glyphIndexForCharacter(at: character)
    return layoutManager.propertyForGlyph(at: glyph).contains(.null)
}

@MainActor @Suite struct MarkdownTextViewTests {
    @Test func hidesMarkersOutsideActiveBlock() {
        let text = "# 标题\n\n正文"
        let view = makeView(text)
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        #expect(isHidden(view, character: 0))
        #expect(isHidden(view, character: 1))   // the space after "#"
        #expect(!isHidden(view, character: 2))  // the title text
    }

    @Test func showsMarkersInActiveBlock() {
        let view = makeView("# 标题\n\n正文")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(!isHidden(view, character: 0))
    }

    @Test func movingCaretIntoABlockRevealsItsMarkers() {
        let text = "# 标题\n\n正文"
        let view = makeView(text)
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        #expect(isHidden(view, character: 0))
        view.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(!isHidden(view, character: 0))
    }

    @Test func caretMoveRestylesOnlyChangedBlocks() {
        let text = "a\n\nb\n\nc"
        let view = makeView(text)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.setSelectedRange(NSRange(location: 7, length: 0))
        let blocks = view.blocks
        #expect(view.lastInvalidatedRange == NSUnionRange(blocks[0].range, blocks[2].range))
        // Moving inside the same block changes nothing.
        view.setSelectedRange(NSRange(location: 6, length: 0))
        #expect(view.lastInvalidatedRange == nil)
    }

    @Test func noRestyleDuringMarkedText() {
        let view = makeView("")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let before = view.restyleCount
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        #expect(view.restyleCount == before)
        view.insertText("中", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.hasMarkedText())
        #expect(view.restyleCount == before + 1)
        #expect(view.string == "中")
    }

    @Test func textChangeCallbackSkipsMarkedText() {
        let view = makeView("")
        var seen: [String] = []
        view.onTextChange = { seen.append($0) }
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(seen.isEmpty)
        view.insertText("中", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(seen == ["中"])
    }

    @Test func settingMarkdownDoesNotFireTextChangeOrRegisterUndo() {
        let view = makeView("start")
        var fired = false
        view.onTextChange = { _ in fired = true }
        view.markdown = "replaced"
        #expect(!fired)
        #expect(view.string == "replaced")
        #expect(view.undoManager?.canUndo != true)
    }

    @Test func restyleDoesNotRegisterUndo() {
        let view = makeView("# 标题")
        view.undoManager?.removeAllActions()
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "# 标题a")
        view.undoManager?.undo()
        #expect(view.string == "# 标题")
        #expect(view.undoManager?.canUndo != true)
    }

    @Test func copyIncludesHiddenMarkers() {
        let view = makeView("**粗**\n\nx")
        view.setSelectedRange(NSRange(location: 8, length: 0))  // caret in the second block: first is concealed
        #expect(isHidden(view, character: 0))
        view.setSelectedRange(NSRange(location: 0, length: 5))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        #expect(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        #expect(pasteboard.string(forType: .string) == "**粗**")
    }

    @Test func readOnlyPaneStartsAtTheTop() {
        // NSTextView keeps the insertion point visible when it resizes; at the end of the text that would
        // scroll a freshly opened review pane down.
        let view = makeView("# 标题\n\n正文", concealAll: true)
        #expect(view.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func concealAllIsReadOnlyAndHidesEverything() {
        let view = makeView("# 标题\n\n**粗**", concealAll: true)
        #expect(!view.isEditable)
        #expect(view.activeBlocks.isEmpty)
        view.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(isHidden(view, character: 0))
        #expect(view.activeBlocks.isEmpty)
    }

    @Test func themeChangeRestylesEverything() {
        let view = makeView("# 标题")
        let before = view.restyleCount
        view.theme = EditorTheme(bodySize: 18)
        #expect(view.restyleCount == before + 1)
    }

    @Test func textColumnGrowsWithTheWindowUpToTheCap() {
        let theme = EditorTheme.default
        // Sides are 12% of the width, so the column is 76% of it.
        #expect(theme.horizontalInset(forWidth: 600) == 72)
        #expect(theme.horizontalInset(forWidth: 1000) == 120)
        // Wide windows stop at maxContentWidth and center the column.
        #expect(theme.horizontalInset(forWidth: 1700) == (1700 - theme.maxContentWidth) / 2)
        // Tiny windows still keep 48 pt on each side.
        #expect(theme.horizontalInset(forWidth: 300) == 48)
    }

    @Test func columnNeverExceedsTheCap() {
        let theme = EditorTheme.default
        for width in stride(from: 400.0, through: 3000.0, by: 100.0) {
            let column = width - 2 * theme.horizontalInset(forWidth: width)
            #expect(column <= theme.maxContentWidth + 0.5)
        }
    }

    @Test func viewUsesTheAdaptiveInset() {
        let view = makeView("x")
        view.setFrameSize(NSSize(width: 1000, height: 400))
        #expect(view.textContainerInset == NSSize(width: 120, height: 56))
        view.setFrameSize(NSSize(width: 1700, height: 400))
        #expect(view.textContainerInset.width == (1700 - EditorTheme.default.maxContentWidth) / 2)
        view.setFrameSize(NSSize(width: 300, height: 400))
        #expect(view.textContainerInset == NSSize(width: 48, height: 56))
    }

    @Test func highlightAddsTemporaryAttributes() {
        let view = makeView("甲乙丙丁甲乙")
        view.highlightRanges([NSRange(location: 0, length: 2), NSRange(location: 4, length: 2)])
        let layoutManager = view.layoutManager!
        #expect(layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil)
        #expect(layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: 4, effectiveRange: nil) != nil)
        #expect(layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: 2, effectiveRange: nil) == nil)
        // Highlights are not part of the text, so they never reach the file.
        #expect(view.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test func editClearsHighlights() {
        let view = makeView("甲乙丙丁")
        view.highlightRanges([NSRange(location: 0, length: 2)])
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.insertText("戊", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.layoutManager!.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil)
        #expect(view.highlightedRanges.isEmpty)
    }

    @Test func highlightMatchesFindsEveryOccurrenceIgnoringCase() {
        let view = makeView("Swift 和 swift 与 SWIFT，还有 设计")
        let count = view.highlightMatches(of: ["swift", "设计"])
        #expect(count == 4)
        #expect(view.highlightedRanges.count == 4)
    }

    @Test func highlightMatchesScrollsToTheFirstMatch() {
        let filler = String(repeating: "填充文字，用来撑高文档。\n\n", count: 60)
        let view = makeView(filler + "目标词在这里")
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        scrollView.documentView = view
        view.setFrameSize(NSSize(width: 600, height: 4000))
        _ = view.highlightMatches(of: ["目标词"])
        #expect(view.highlightedRanges.count == 1)
        #expect(scrollView.contentView.bounds.minY > 0)
    }

    @Test func emptyTermsHighlightNothing() {
        let view = makeView("内容")
        #expect(view.highlightMatches(of: []) == 0)
        #expect(view.highlightMatches(of: [""]) == 0)
    }

    @Test func headingGetsHeadingFont() {
        let view = makeView("# 标题\n\n正文")
        let heading = view.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        let body = view.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(heading?.pointSize == 28)
        #expect(body?.pointSize == 15)
    }
}
