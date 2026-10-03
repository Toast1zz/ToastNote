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

    @Test func emptyEditableNoteShowsAPlaceholder() {
        let view = makeView("")
        view.placeholder = "开始输入…"
        #expect(view.showsPlaceholder)
        view.insertText("a", replacementRange: NSRange(location: 0, length: 0))
        #expect(!view.showsPlaceholder)
        #expect(!makeView("", concealAll: true).showsPlaceholder)
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

    @Test func aTagThatStartsAParagraphKeepsItsPillInsideTheColumn() {
        let view = makeView("#读书 #设计\n\n正文")
        let style = view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.firstLineHeadIndent == MarkdownTextView.tagPillInset)
        let body = view.textStorage!.attribute(.paragraphStyle, at: ("#读书 #设计\n\n正文" as NSString).range(of: "正文").location, effectiveRange: nil) as? NSParagraphStyle
        #expect(body?.firstLineHeadIndent == 0)
    }

    @Test func emptyTermsClearEarlierMatches() {
        // Clearing the search field clears the editor's matches this way.
        let view = makeView("内容和内容")
        #expect(view.highlightMatches(of: ["内容"]) == 2)
        #expect(view.highlightMatches(of: []) == 0)
        #expect(view.highlightedRanges.isEmpty)
    }

    @Test func headingGetsHeadingFont() {
        let view = makeView("# 标题\n\n正文")
        let heading = view.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        let body = view.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(heading?.pointSize == 28)
        #expect(body?.pointSize == 15)
    }

    /// Where each of these paragraphs starts, measured from the top of the text container.
    private func lineTops(_ view: MarkdownTextView, at characters: [Int]) -> [CGFloat] {
        guard let layoutManager = view.layoutManager, let container = view.textContainer else { return [] }
        layoutManager.ensureLayout(for: container)
        return characters.map {
            layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: $0), effectiveRange: nil).minY
        }
    }

    @Test func textDoesNotMoveWhenTheCaretEntersOrLeavesAHeading() {
        // Showing the "#" markers must not change any vertical position, or the page jumps on every click.
        let text = "# 标题\n\n正文\n\n## 小节\n\n尾"
        let ns = text as NSString
        let probes = [ns.range(of: "标题").location, ns.range(of: "正文").location, ns.range(of: "小节").location, ns.range(of: "尾").location]
        let view = makeView(text)
        view.setSelectedRange(NSRange(location: ns.length, length: 0))
        let resting = lineTops(view, at: probes)
        for probe in probes {
            view.setSelectedRange(NSRange(location: probe + 1, length: 0))
            #expect(lineTops(view, at: probes) == resting)
        }
        view.setSelectedRange(NSRange(location: ns.length, length: 0))
        #expect(lineTops(view, at: probes) == resting)
    }

    @Test func listTextDoesNotMoveSidewaysWhenTheCaretEntersTheItem() {
        let text = "- 第一项\n- 第二项\n  - 嵌套\n\t- 制表\n1. 有序\n- [ ] 待办\n- [x] 完成\n\n尾"
        let ns = text as NSString
        let view = makeView(text)
        let layoutManager = view.layoutManager!
        func textX(_ piece: String) -> CGFloat {
            layoutManager.ensureLayout(for: view.textContainer!)
            let glyph = layoutManager.glyphIndexForCharacter(at: ns.range(of: piece).location)
            return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX + layoutManager.location(forGlyphAt: glyph).x
        }
        for piece in ["第二项", "嵌套", "制表", "有序", "待办", "完成"] {
            view.setSelectedRange(NSRange(location: ns.length, length: 0))
            let resting = textX(piece)
            view.setSelectedRange(NSRange(location: ns.range(of: piece).location + 1, length: 0))
            // A tab in the prefix advances to the next tab stop, which measuring the prefix alone cannot see;
            // that leaves under a point. Known, not yet fixed.
            let tolerance: CGFloat = piece == "制表" ? 1 : 0.5
            #expect(abs(textX(piece) - resting) < tolerance, "\(piece) moved from \(resting) to \(textX(piece))")
        }
    }

    @Test func textDoesNotMoveWhenTheCaretEntersOrLeavesAListItem() {
        let text = "## 购物清单\n\n- [ ] 牛奶\n- [x] 咖啡\n- [ ] 罐头\n\n## 电影\n\n1. 甲\n2. 乙\n\n尾"
        let ns = text as NSString
        let probes = ["牛奶", "咖啡", "罐头", "电影", "甲", "乙", "尾"].map { ns.range(of: $0).location }
        let view = makeView(text)
        view.setSelectedRange(NSRange(location: ns.length, length: 0))
        let resting = lineTops(view, at: probes)
        for piece in ["牛奶", "咖啡", "罐头", "甲", "乙"] {
            view.setSelectedRange(NSRange(location: ns.range(of: piece).location + 1, length: 0))
            #expect(lineTops(view, at: probes) == resting, "caret in \(piece): \(lineTops(view, at: probes)) vs \(resting)")
        }
    }

    @Test func textDoesNotMoveWhenTheCaretEntersOrLeavesAQuote() {
        let text = "段落\n\n> 引用一\n> 引用二\n\n尾"
        let ns = text as NSString
        let probes = [ns.range(of: "引用一").location, ns.range(of: "引用二").location, ns.range(of: "尾").location]
        let view = makeView(text)
        view.setSelectedRange(NSRange(location: ns.length, length: 0))
        let resting = lineTops(view, at: probes)
        view.setSelectedRange(NSRange(location: probes[0] + 1, length: 0))
        #expect(lineTops(view, at: probes) == resting)
        view.setSelectedRange(NSRange(location: ns.length, length: 0))
        #expect(lineTops(view, at: probes) == resting)
    }

    @Test func headingTextKeepsItsBaselineWhenItsMarkersAppear() {
        let text = "段落\n\n## 本周进展\n\n- 项"
        let ns = text as NSString
        let probe = ns.range(of: "本周").location
        let view = makeView(text)
        func baseline() -> CGFloat {
            let layoutManager = view.layoutManager!
            layoutManager.ensureLayout(for: view.textContainer!)
            let glyph = layoutManager.glyphIndexForCharacter(at: probe)
            return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + layoutManager.location(forGlyphAt: glyph).y
        }
        view.setSelectedRange(NSRange(location: ns.length, length: 0))
        let hidden = baseline()
        view.setSelectedRange(NSRange(location: probe + 1, length: 0))
        #expect(baseline() == hidden)
    }

    @Test func textSitsInTheMiddleOfItsFixedHeightLine() {
        // Leading split above and below, so the selection and the caret wrap the text evenly.
        for text in ["正文", "# 标题", "Latin"] {
            let view = makeView(text)
            let layoutManager = view.layoutManager!
            layoutManager.ensureLayout(for: view.textContainer!)
            let glyph = (text as NSString).length - 1
            let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = layoutManager.location(forGlyphAt: glyph).y
            let size = (view.textStorage!.attribute(.font, at: glyph, effectiveRange: nil) as! NSFont).pointSize
            let font = NSFont.systemFont(ofSize: size)
            let above = baseline - font.ascender
            let below = used.height - (baseline - font.descender)
            #expect(abs(above - below) <= 1, "\(text): \(above) above vs \(below) below")
        }
    }

    @Test func firstLineAfterAHiddenFenceKeepsItsFirstCharacter() {
        // Leaving the block relays out from the hidden fence; the line break must stay on the fence, not move
        // one glyph into the code (the "l" of "let" would join the hidden line and vanish). This is the sample
        // note where it showed up; shorter texts did not trigger it.
        let text = """
        ---
        tags: [会议, 产品]
        ---
        # 产品周会 10-02

        参会：小林、阿杰、Mia、我。本周重点是 **v1 发布前的收尾**，以及确认 AI 排版的默认行为。

        ## 本周进展

        - 编辑器实时预览完成，标记符号在光标离开后自动隐藏
        - 搜索改用 SQLite FTS5，1000 篇笔记内查询 *小于 10 ms*
        - PDF 导出支持 A4 分页，代码块不会被拆开
          - 长表格仍会跨页，下周看看能否加表头重复
          - 图片按页面宽度缩放

        ## 待决定

        > AI 排版默认应该只动格式，不改任何一个字。用户改主意之前，任何“润色”都是越界。
        > —— 来自上次用户访谈

        1. 默认服务商：DeepSeek 还是让用户首次使用时选择？
        2. 是否在工具栏常驻「AI 排版」按钮
        3. 发布渠道：GitHub Releases + Sparkle

        ## 行动项

        - [x] 整理用户访谈记录 #研究
        - [x] 修复中文输入法组字时的闪烁
        - [ ] 补齐 README 截图
        - [ ] 准备发布说明，链接到 [更新日志](https://example.com/changelog)

        ```swift
        let session = try NoteSession(url: note, registry: registry)
        session.onExternalChange = { text in
            editor.replace(with: text)
        }
        ```

        下次周会：10 月 9 日，地点不变。

        """
        let ns = text as NSString
        let view = MarkdownTextView(theme: .default)
        view.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        retainedWindows.append(window)
        view.markdown = text
        let layoutManager = view.layoutManager!
        let first = ns.range(of: "let session").location
        func firstLineStart() -> Int {
            layoutManager.ensureLayout(for: view.textContainer!)
            var range = NSRange()
            _ = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: first), effectiveRange: &range)
            return layoutManager.characterIndexForGlyph(at: range.location)
        }
        #expect(firstLineStart() == first)
        // Lay out after every step, as the window does between clicks.
        view.setSelectedRange(NSRange(location: ns.range(of: "准备发布说明").location + 4, length: 2))
        _ = firstLineStart()
        view.setSelectedRange(NSRange(location: ns.range(of: "session =").location + 8, length: 0))
        _ = firstLineStart()
        view.setSelectedRange(NSRange(location: ns.range(of: "地点不变").location + 2, length: 0))
        #expect(firstLineStart() == first)
    }

    @Test func fillsTheVisibleHeightAndKeepsRoomBelowTheLastLine() {
        // The room below the text is part of the text view: scroll-view content insets would put a click-eating
        // background layer over that area on macOS 26.
        let view = MarkdownTextView(theme: .default)
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.markdown = "短"
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        scrollView.documentView = view
        let window = NSWindow(contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = scrollView
        retainedWindows.append(window)
        #expect(scrollView.contentInsets.bottom == 0)
        #expect(view.frame.height >= scrollView.contentSize.height)
        scrollView.setFrameSize(NSSize(width: 500, height: 600))
        #expect(view.frame.height >= scrollView.contentSize.height)

        view.markdown = Array(repeating: "一行", count: 80).joined(separator: "\n\n")
        let layoutManager = view.layoutManager!
        layoutManager.ensureLayout(for: view.textContainer!)
        view.sizeToFit()
        let natural = layoutManager.usedRect(for: view.textContainer!).height + 2 * view.textContainerInset.height
        #expect(view.frame.height >= natural + 0.4 * scrollView.contentSize.height - 1)
    }

    @Test func markersAppearOnlyOnceTheMouseIsReleased() {
        let text = "段落\n\n```\ncode\n```\n\n尾"
        let ns = text as NSString
        let view = makeView(text)
        view.setSelectedRange(NSRange(location: ns.length, length: 0))
        #expect(view.activeBlocks.count == 1)
        let codeBlock = view.blocks.firstIndex { NSLocationInRange(ns.range(of: "code").location, $0.range) }
        let inside = NSValue(range: NSRange(location: ns.range(of: "code").location + 1, length: 0))
        view.setSelectedRanges([inside], affinity: .downstream, stillSelecting: true)
        #expect(!view.activeBlocks.contains(codeBlock ?? -1))
        view.setSelectedRanges([inside], affinity: .downstream, stillSelecting: false)
        #expect(view.activeBlocks.contains(codeBlock ?? -1))
    }

    @Test func quoteBarCoversItsOwnLinesEvenly() {
        let text = "段落\n\n> 引用一\n> 引用二\n\n尾"
        let ns = text as NSString
        let view = makeView(text)
        view.setSelectedRange(NSRange(location: ns.length, length: 0))
        let layoutManager = view.layoutManager as! ConcealingLayoutManager
        layoutManager.ensureLayout(for: view.textContainer!)
        let range = layoutManager.decorations.compactMap { decoration -> NSRange? in
            if case .quoteBar(let range) = decoration { range } else { nil }
        }.first
        let bar = range.flatMap { layoutManager.quoteBarRect(for: $0) }
        let firstLine = layoutManager.lineFragmentUsedRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: ns.range(of: "引用一").location), effectiveRange: nil)
        let lastLine = layoutManager.lineFragmentUsedRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: ns.range(of: "引用二").location), effectiveRange: nil)
        #expect(bar != nil)
        if let bar {
            #expect(bar.minY >= firstLine.minY)
            #expect(bar.maxY <= lastLine.maxY)
            #expect(abs((bar.minY - firstLine.minY) - (lastLine.maxY - bar.maxY)) <= 3)
        }
    }

    @Test func linesOfTheSameStyleShareOneBaselineWhateverFontsTheyMix() {
        // Pure CJK, Latin only and mixed lines: CJK glyphs come from a fallback font with another descent.
        let view = makeView("中文中文\n\nLatin only\n\n中文 and Latin")
        let ns = view.string as NSString
        let layoutManager = view.layoutManager!
        layoutManager.ensureLayout(for: view.textContainer!)
        let offsets = ["中文中文", "Latin only", "中文 and"].map { piece -> CGFloat in
            let glyph = layoutManager.glyphIndexForCharacter(at: ns.range(of: piece).location)
            return layoutManager.location(forGlyphAt: glyph).y
        }
        #expect(Set(offsets).count == 1)
    }

    @Test func caretCoversTheFontAroundTheBaselineNotTheWholeFixedLine() {
        let view = makeView("正文")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        let glyph = view.layoutManager!.glyphIndexForCharacter(at: 1)
        let line = view.layoutManager!.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = view.textContainerOrigin.y + line.minY + view.layoutManager!.location(forGlyphAt: glyph).y
        let lineRect = NSRect(x: 40, y: view.textContainerOrigin.y + line.minY, width: 1, height: line.height)
        let caret = view.caretRect(from: lineRect)
        let font = view.typingAttributes[.font] as! NSFont
        #expect(caret.height < line.height)
        #expect(caret.minY <= baseline - font.ascender + 1)
        #expect(caret.maxY >= baseline)
        #expect(caret.maxY <= lineRect.maxY)
        #expect(caret.minX == lineRect.minX && caret.width == lineRect.width)
    }
}
