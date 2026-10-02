import AppKit
import Foundation
import Testing
@testable import EditorKit

@MainActor
private var retainedWindows: [NSWindow] = []

@MainActor
private func makeView(_ text: String, caret: Int? = nil) -> MarkdownTextView {
    let view = MarkdownTextView(theme: .default)
    view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = view
    retainedWindows.append(window)
    view.markdown = text
    view.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
    view.layoutManager?.ensureLayout(for: view.textContainer!)
    return view
}

@MainActor @Suite struct DecorationTests {
    @Test func toggleOpenTask() {
        let view = makeView("- [ ] a")
        view.toggleTask(atCharacterIndex: 0)
        #expect(view.string == "- [x] a")
    }

    @Test func toggleDoneTask() {
        let view = makeView("- [x] a")
        view.toggleTask(atCharacterIndex: 3)
        #expect(view.string == "- [ ] a")
    }

    @Test func toggleIsUndoable() {
        let view = makeView("- [ ] a")
        view.undoManager?.removeAllActions()
        view.toggleTask(atCharacterIndex: 0)
        #expect(view.undoManager?.undoActionName == "切换任务")
        view.undoManager?.undo()
        #expect(view.string == "- [ ] a")
    }

    @Test func toggleReportsTextChange() {
        let view = makeView("- [ ] a")
        var seen: [String] = []
        view.onTextChange = { seen.append($0) }
        view.toggleTask(atCharacterIndex: 0)
        #expect(seen == ["- [x] a"])
    }

    @Test func toggleOutsideATaskIsANoOp() {
        let view = makeView("plain\n\n- item")
        view.toggleTask(atCharacterIndex: 0)
        view.toggleTask(atCharacterIndex: 8)
        #expect(view.string == "plain\n\n- item")
    }

    @Test func clickOnCheckboxRectToggles() throws {
        let view = makeView("- [ ] a\n\nb")  // caret in the second block: the checkbox is drawn
        let rect = try #require(view.checkboxRect(forCharacterIndex: 0))
        let windowPoint = view.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: windowPoint, modifierFlags: [], timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        view.mouseDown(with: event)
        #expect(view.string == "- [x] a\n\nb")
    }

    @Test func noCheckboxRectWhileBlockIsActive() {
        let view = makeView("- [ ] a\n\nb", caret: 3)
        #expect(view.checkboxRect(forCharacterIndex: 0) == nil)
    }

    @Test func linkURLLookup() {
        let view = makeView("[文字](https://x.y) 和 https://a.b")
        #expect(view.linkURL(atCharacterIndex: 2) == URL(string: "https://x.y"))
        #expect(view.linkURL(atCharacterIndex: 25) == URL(string: "https://a.b"))
        #expect(view.linkURL(atCharacterIndex: 18) == nil)
    }
}
