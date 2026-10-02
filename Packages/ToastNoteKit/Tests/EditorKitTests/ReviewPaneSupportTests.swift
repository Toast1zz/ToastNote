import AppKit
import Foundation
import Testing
@testable import EditorKit

@MainActor private var retainedWindows: [NSWindow] = []

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

/// What the AI review window needs from the editor: one-step edits, block geometry for synced scrolling,
/// per-block labels and a fixed gutter.
@MainActor @Suite struct ReviewPaneSupportTests {
    @Test func applyEditReplacesARangeInOneUndoStep() {
        let view = makeView("甲\n\n乙\n\n丙")
        view.undoManager?.removeAllActions()
        view.applyEdit(range: NSRange(location: 3, length: 1), replacement: "# 乙乙", actionName: "AI 排版")
        #expect(view.string == "甲\n\n# 乙乙\n\n丙")
        #expect(view.undoManager?.undoActionName == "AI 排版")
        view.undoManager?.undo()
        #expect(view.string == "甲\n\n乙\n\n丙")
    }

    @Test func applyEditReportsTheTextChange() {
        let view = makeView("甲")
        var seen: [String] = []
        view.onTextChange = { seen.append($0) }
        view.applyEdit(range: NSRange(location: 0, length: 1), replacement: "乙", actionName: "AI 排版")
        #expect(seen == ["乙"])
    }

    @Test func blockTopsIncreaseDownTheDocument() throws {
        let view = makeView("# 标题\n\n第一段\n\n第二段\n\n第三段")
        let tops = try (0..<view.blocks.count).map { try #require(view.blockTop(at: $0)) }
        #expect(tops == tops.sorted())
        #expect(Set(tops).count == tops.count)
    }

    @Test func blockIndexAtYFindsTheBlockAndClamps() throws {
        let view = makeView("# 标题\n\n第一段\n\n第二段")
        let second = try #require(view.blockTop(at: 2))
        #expect(view.blockIndexAt(y: second + 2) == 2)
        #expect(view.blockIndexAt(y: -50) == 0)
        #expect(view.blockIndexAt(y: 100_000) == view.blocks.count - 1)
    }

    @Test func blockIndexAtYOnAnEmptyDocumentIsNil() {
        #expect(makeView("").blockIndexAt(y: 10) == nil)
        #expect(makeView("").blockTop(at: 0) == nil)
    }

    @Test func fixedHorizontalInsetOverridesTheAdaptiveOne() {
        let view = makeView("x", concealAll: true)
        view.fixedHorizontalInset = 72
        view.setFrameSize(NSSize(width: 1200, height: 400))
        #expect(view.textContainerInset.width == 72)
        view.fixedHorizontalInset = nil
        view.setFrameSize(NSSize(width: 1201, height: 400))
        #expect(view.textContainerInset.width == EditorTheme.default.horizontalInset(forWidth: 1201))
    }

    @Test func blockLabelsAreKeptPerBlock() {
        let view = makeView("甲\n\n乙")
        view.blockLabels = [1: "变为标题"]
        #expect(view.blockLabels == [1: "变为标题"])
    }
}
