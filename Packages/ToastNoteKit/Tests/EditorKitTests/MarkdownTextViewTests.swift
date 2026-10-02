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

    @Test func contentIsCenteredWithMinimumSideInset() {
        let view = makeView("x")
        view.setFrameSize(NSSize(width: 1000, height: 400))
        #expect(view.textContainerInset == NSSize(width: 140, height: 56))  // (1000 - 720) / 2
        view.setFrameSize(NSSize(width: 600, height: 400))
        #expect(view.textContainerInset == NSSize(width: 48, height: 56))   // narrow window keeps 48 pt sides
    }

    @Test func headingGetsHeadingFont() {
        let view = makeView("# 标题\n\n正文")
        let heading = view.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        let body = view.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(heading?.pointSize == 28)
        #expect(body?.pointSize == 15)
    }
}
