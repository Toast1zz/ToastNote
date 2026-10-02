import AppKit
import Foundation
import Testing
@testable import EditorKit

private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

/// Applies an edit the way the text view does, to check the resulting document.
private func apply(_ edit: TextEdit, to text: String) -> String {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

@Suite struct EditingCommandsTests {
    @Test func wrapSelection() {
        let edit = EditingCommands.toggleWrap("**", text: "abc" as NSString, selection: r(0, 3))
        #expect(apply(edit, to: "abc") == "**abc**")
        #expect(edit.selectionAfter == r(2, 3))
    }

    @Test func unwrapSelection() {
        let edit = EditingCommands.toggleWrap("**", text: "**abc**" as NSString, selection: r(2, 3))
        #expect(apply(edit, to: "**abc**") == "abc")
        #expect(edit.selectionAfter == r(0, 3))
    }

    @Test func unwrapWhenMarkersAreInsideTheSelection() {
        let edit = EditingCommands.toggleWrap("**", text: "**abc**" as NSString, selection: r(0, 7))
        #expect(apply(edit, to: "**abc**") == "abc")
        #expect(edit.selectionAfter == r(0, 3))
    }

    @Test func emptySelectionInsertsPair() {
        let edit = EditingCommands.toggleWrap("*", text: "" as NSString, selection: r(0, 0))
        #expect(apply(edit, to: "") == "**")
        #expect(edit.selectionAfter == r(1, 0))
    }

    @Test func emptySelectionBetweenMarkersRemovesPair() {
        let edit = EditingCommands.toggleWrap("*", text: "**" as NSString, selection: r(1, 0))
        #expect(apply(edit, to: "**") == "")
        #expect(edit.selectionAfter == r(0, 0))
    }

    @Test func italicInsideBoldIsWrappedNotUnwrapped() {
        let edit = EditingCommands.toggleWrap("*", text: "**abc**" as NSString, selection: r(2, 3))
        #expect(apply(edit, to: "**abc**") == "***abc***")
    }

    @Test func wrapKeepsTextAroundTheSelection() {
        let edit = EditingCommands.toggleWrap("~~", text: "前 中文 后" as NSString, selection: r(2, 2))
        #expect(apply(edit, to: "前 中文 后") == "前 ~~中文~~ 后")
        #expect(edit.selectionAfter == r(4, 2))
    }

    @Test func linkWrapsSelection() {
        let edit = EditingCommands.insertLink(text: "文字" as NSString, selection: r(0, 2))
        #expect(apply(edit, to: "文字") == "[文字]()")
        #expect(edit.selectionAfter == r(5, 0))
    }

    @Test func linkWithEmptySelection() {
        let edit = EditingCommands.insertLink(text: "" as NSString, selection: r(0, 0))
        #expect(apply(edit, to: "") == "[]()")
        #expect(edit.selectionAfter == r(1, 0))
    }

    @Test func continueBullet() throws {
        let edit = try #require(EditingCommands.newline(text: "- a" as NSString, caret: 3))
        #expect(apply(edit, to: "- a") == "- a\n- ")
        #expect(edit.selectionAfter == r(6, 0))
    }

    @Test func continueOrdered() throws {
        let edit = try #require(EditingCommands.newline(text: "9. a" as NSString, caret: 4))
        #expect(apply(edit, to: "9. a") == "9. a\n10. ")
    }

    @Test func continueTask() throws {
        let edit = try #require(EditingCommands.newline(text: "- [x] a" as NSString, caret: 7))
        #expect(apply(edit, to: "- [x] a") == "- [x] a\n- [ ] ")
    }

    @Test func continueKeepsIndentAndBulletCharacter() throws {
        let edit = try #require(EditingCommands.newline(text: "  * a" as NSString, caret: 5))
        #expect(apply(edit, to: "  * a") == "  * a\n  * ")
    }

    @Test func splitsItemWhenCaretIsInTheMiddle() throws {
        let edit = try #require(EditingCommands.newline(text: "- ab" as NSString, caret: 3))
        #expect(apply(edit, to: "- ab") == "- a\n- b")
    }

    @Test func emptyItemExitsList() throws {
        let text = "- a\n- "
        let edit = try #require(EditingCommands.newline(text: text as NSString, caret: 6))
        #expect(apply(edit, to: text) == "- a\n")
        #expect(edit.selectionAfter == r(4, 0))
    }

    @Test func emptyTaskItemExitsList() throws {
        let text = "- [ ] "
        let edit = try #require(EditingCommands.newline(text: text as NSString, caret: 6))
        #expect(apply(edit, to: text) == "")
    }

    @Test func newlineOutsideAListIsNotHandled() {
        #expect(EditingCommands.newline(text: "plain" as NSString, caret: 5) == nil)
        #expect(EditingCommands.newline(text: "- a" as NSString, caret: 1) == nil)  // caret inside the marker
    }

    @Test func indentListItem() throws {
        let edit = try #require(EditingCommands.indent(text: "- a" as NSString, selection: r(3, 0), outdent: false))
        #expect(apply(edit, to: "- a") == "  - a")
        #expect(edit.selectionAfter == r(5, 0))
    }

    @Test func outdentListItem() throws {
        let edit = try #require(EditingCommands.indent(text: "  - a" as NSString, selection: r(5, 0), outdent: true))
        #expect(apply(edit, to: "  - a") == "- a")
        #expect(edit.selectionAfter == r(3, 0))
    }

    @Test func outdentAtTopLevelDoesNothing() {
        #expect(EditingCommands.indent(text: "- a" as NSString, selection: r(3, 0), outdent: true) == nil)
    }

    @Test func indentIgnoresNonListLines() {
        #expect(EditingCommands.indent(text: "plain" as NSString, selection: r(0, 0), outdent: false) == nil)
    }

    @Test func indentsEverySelectedListLine() throws {
        let text = "- a\n- b"
        let edit = try #require(EditingCommands.indent(text: text as NSString, selection: r(0, 7), outdent: false))
        #expect(apply(edit, to: text) == "  - a\n  - b")
    }
}

@MainActor private var retainedWindows: [NSWindow] = []

@MainActor
private func makeView(_ text: String, selection: NSRange) -> MarkdownTextView {
    let view = MarkdownTextView(theme: .default)
    view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = view
    retainedWindows.append(window)
    view.markdown = text
    view.setSelectedRange(selection)
    return view
}

@MainActor @Suite struct EditingCommandsViewTests {
    @Test func boldActionWrapsSelectionInOneUndoStep() {
        let view = makeView("abc", selection: r(0, 3))
        view.undoManager?.removeAllActions()
        view.toggleBold(nil)
        #expect(view.string == "**abc**")
        #expect(view.selectedRange() == r(2, 3))
        view.undoManager?.undo()
        #expect(view.string == "abc")
    }

    @Test func returnContinuesTheList() {
        let view = makeView("- a", selection: r(3, 0))
        view.insertNewline(nil)
        #expect(view.string == "- a\n- ")
        #expect(view.selectedRange() == r(6, 0))
    }

    @Test func returnOutsideAListInsertsPlainNewline() {
        let view = makeView("abc", selection: r(3, 0))
        view.insertNewline(nil)
        #expect(view.string == "abc\n")
    }

    @Test func tabIndentsListItemAndBacktabOutdents() {
        let view = makeView("- a", selection: r(3, 0))
        view.insertTab(nil)
        #expect(view.string == "  - a")
        view.insertBacktab(nil)
        #expect(view.string == "- a")
    }

    @Test func pasteTakesPlainTextFromRichPasteboard() {
        let view = makeView("", selection: r(0, 0))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        let rich = NSAttributedString(string: "粗体", attributes: [.font: NSFont.boldSystemFont(ofSize: 30)])
        pasteboard.writeObjects([rich])
        #expect(view.readablePasteboardTypes == [.string])
        _ = view.readSelection(from: pasteboard)
        #expect(view.string == "粗体")
        let font = view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == 15)
    }
}
