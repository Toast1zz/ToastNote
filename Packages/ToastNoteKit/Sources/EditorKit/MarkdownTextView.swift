import AppKit
import Foundation

/// The live-preview editor: the block under the caret shows raw Markdown, all others show their rendering.
@MainActor
public final class MarkdownTextView: NSTextView {
    public var onTextChange: ((String) -> Void)?
    public private(set) var blocks: [Block] = []
    public private(set) var activeBlocks = IndexSet()
    /// Incremented once per full parse + style pass; lets tests prove when restyling did (not) happen.
    public private(set) var restyleCount = 0
    public var theme: EditorTheme {
        didSet {
            updateLayoutInsets()
            restyleAll()
        }
    }

    /// Union of the blocks whose glyphs were invalidated by the last caret move; nil when none changed.
    private(set) var lastInvalidatedRange: NSRange?
    /// The text range the last parse + style pass wrote attributes to; nil when nothing needed writing.
    private(set) var lastRestyledRange: NSRange?
    /// One entry per block (plus the tail after the last block) describing everything that decides how it
    /// looks; comparing two passes shows which part of the document needs new attributes.
    private var regionSignatures: [RegionSignature] = []
    /// True between the moment the text is about to change and the restyle that follows. The selection
    /// moves during that window, but `blocks` still describe the old text, so it must not be used.
    private var blocksAreStale = false

    private struct RegionSignature: Equatable {
        /// Where the region starts: the end of the previous block, so blank lines belong to the next block.
        var start: Int
        var hash: Int
    }
    /// Decorations to draw (Task 13).
    private(set) var decorations: [Decoration] = []

    /// Replaces the adaptive side inset, e.g. for the narrow panes of the review window.
    public var fixedHorizontalInset: CGFloat? {
        didSet { updateLayoutInsets() }
    }

    /// Short labels drawn in the left gutter next to a block (block index → text), with a thin accent bar.
    public var blockLabels: [Int: String] = [:] {
        didSet { publishBlockLabels() }
    }

    private let concealingLayoutManager: ConcealingLayoutManager
    private let concealAll: Bool

    public init(theme: EditorTheme, concealAll: Bool = false) {
        self.theme = theme
        self.concealAll = concealAll
        // TextKit 1 chain, built explicitly: storage -> concealing layout manager -> container.
        let storage = NSTextStorage()
        let layoutManager = ConcealingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        concealingLayoutManager = layoutManager
        super.init(frame: .zero, textContainer: container)

        isRichText = true
        allowsUndo = true
        isEditable = !concealAll
        isSelectable = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        typingAttributes = theme.attributes(for: TextStyle(role: .body))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Content

    /// The Markdown source. Setting it never registers undo and never calls `onTextChange`.
    public var markdown: String {
        get { string }
        set {
            blocksAreStale = true
            undoManager?.disableUndoRegistration()
            string = newValue
            undoManager?.enableUndoRegistration()
            undoManager?.removeAllActions()
            restyleAll()
        }
    }

    // MARK: Restyling

    /// Full pass: used when the whole document or the theme changes.
    public func restyleAll() {
        restyle(incremental: false)
    }

    /// After an edit only the part of the document whose blocks changed gets new attributes. Attributes
    /// travel with the text, so unchanged blocks before and after the edit keep theirs.
    private func restyleAfterEdit() {
        restyle(incremental: true)
    }

    private func restyle(incremental: Bool) {
        let signpost = EditorSignposts.signposter
        let state = signpost.beginInterval("restyle")
        defer { signpost.endInterval("restyle", state) }

        let text = string as NSString
        blocks = BlockParser.parse(string)
        blocksAreStale = false
        activeBlocks = concealAll ? [] : blocks.indices(intersecting: selectedRange())
        let result = MarkdownStyler.style(blocks: blocks, text: text, active: activeBlocks, concealAll: concealAll)

        let signatures = makeSignatures(text: text)
        var region = NSRange(location: 0, length: text.length)
        if incremental, let changed = changedRegion(old: regionSignatures, new: signatures, textLength: text.length) {
            region = changed
        } else if incremental, regionSignatures.count == signatures.count {
            // Nothing that affects appearance changed (for example an edit inside a hidden marker).
            region = NSRange(location: 0, length: 0)
        }
        regionSignatures = signatures
        lastRestyledRange = region.length > 0 ? region : nil
        apply(result, in: region)
        restyleCount += 1
    }

    private func makeSignatures(text: NSString) -> [RegionSignature] {
        var signatures: [RegionSignature] = []
        // A region starts after the previous block's line break, so that break is restyled with that block.
        var previousEnd = 0
        for (index, block) in blocks.enumerated() {
            var hasher = Hasher()
            hasher.combine(block.kind)
            hasher.combine(!concealAll && activeBlocks.contains(index))
            hasher.combine(text.substring(with: NSRange(location: previousEnd, length: max(block.range.location - previousEnd, 0))))
            hasher.combine(text.substring(with: block.range))
            signatures.append(RegionSignature(start: previousEnd, hash: hasher.finalize()))
            previousEnd = min(NSMaxRange(block.range) + 1, text.length)
        }
        var tail = Hasher()
        tail.combine(text.substring(from: min(previousEnd, text.length)))
        signatures.append(RegionSignature(start: previousEnd, hash: tail.finalize()))
        return signatures
    }

    /// The range between the common prefix and suffix of two signature lists; nil when there is no
    /// previous pass or the lists differ in a way that cannot be localized.
    private func changedRegion(old: [RegionSignature], new: [RegionSignature], textLength: Int) -> NSRange? {
        guard !old.isEmpty else { return nil }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix].hash == new[prefix].hash { prefix += 1 }
        if prefix == old.count && prefix == new.count { return NSRange(location: 0, length: 0) }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - 1 - suffix].hash == new[new.count - 1 - suffix].hash { suffix += 1 }
        let start = prefix < new.count ? new[prefix].start : textLength
        let end = suffix > 0 ? new[new.count - suffix].start : textLength
        return NSRange(location: min(start, end), length: max(end - start, 0))
    }

    /// Writes styles for `range` and publishes the hidden set. Attribute-only edits never touch undo.
    private func apply(_ result: StyleResult, in range: NSRange) {
        guard let storage = textStorage else { return }
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }

        let base = theme.attributes(for: TextStyle(role: .body))
        storage.beginEditing()
        if range.length > 0 {
            storage.setAttributes(base, range: range)
            var cache: [TextStyle: [NSAttributedString.Key: Any]] = [:]
            for run in result.runs {
                let clipped = NSIntersectionRange(run.range, range)
                guard clipped.length > 0 else { continue }
                let attributes = cache[run.style] ?? theme.attributes(for: run.style)
                cache[run.style] = attributes
                storage.addAttributes(attributes, range: clipped)
            }
        }
        concealingLayoutManager.hidden = result.hidden.reduce(into: IndexSet()) { set, hidden in
            if hidden.length > 0 { set.insert(integersIn: hidden.location..<NSMaxRange(hidden)) }
        }
        storage.endEditing()
        if range.length > 0 {
            concealingLayoutManager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            concealingLayoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }
        decorations = result.decorations
        concealingLayoutManager.decorations = result.decorations
        concealingLayoutManager.theme = theme
        publishBlockLabels()
        typingAttributes = base
        needsDisplay = true
    }

    /// Caret moved: only blocks whose active state changed need new glyphs and attributes.
    private func updateActiveBlocks() {
        guard !concealAll, !hasMarkedText(), !blocksAreStale else { return }
        let newActive = blocks.indices(intersecting: selectedRange())
        guard newActive != activeBlocks else {
            lastInvalidatedRange = nil
            return
        }
        let changed = newActive.symmetricDifference(activeBlocks)
        activeBlocks = newActive
        var union: NSRange?
        for index in changed where index < blocks.count {
            union = union.map { NSUnionRange($0, blocks[index].range) } ?? blocks[index].range
        }
        guard let union else { return }
        lastInvalidatedRange = union
        let text = string as NSString
        let result = MarkdownStyler.style(blocks: blocks, text: text, active: activeBlocks, concealAll: false)
        apply(result, in: union)
        regionSignatures = makeSignatures(text: text)
    }

    // MARK: Editing commands (spec §7.5)

    /// Applies an edit through the normal text-change path so it is a single undo step.
    private func perform(_ edit: TextEdit, actionName: String? = nil) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selectionAfter)
        if let actionName { undoManager?.setActionName(actionName) }
    }

    private func wrapSelection(_ marker: String, actionName: String) {
        perform(EditingCommands.toggleWrap(marker, text: string as NSString, selection: selectedRange()), actionName: actionName)
    }

    @objc public func toggleBold(_ sender: Any?) { wrapSelection("**", actionName: "粗体") }
    @objc public func toggleItalic(_ sender: Any?) { wrapSelection("*", actionName: "斜体") }
    @objc public func toggleStrikethrough(_ sender: Any?) { wrapSelection("~~", actionName: "删除线") }
    @objc public func toggleInlineCode(_ sender: Any?) { wrapSelection("`", actionName: "行内代码") }
    @objc public func insertMarkdownLink(_ sender: Any?) {
        perform(EditingCommands.insertLink(text: string as NSString, selection: selectedRange()), actionName: "插入链接")
    }

    public override func insertNewline(_ sender: Any?) {
        if !hasMarkedText(), selectedRange().length == 0,
           let edit = EditingCommands.newline(text: string as NSString, caret: selectedRange().location) {
            perform(edit)
        } else {
            super.insertNewline(sender)
        }
    }

    public override func insertTab(_ sender: Any?) {
        if let edit = EditingCommands.indent(text: string as NSString, selection: selectedRange(), outdent: false) {
            perform(edit)
        } else {
            super.insertTab(sender)
        }
    }

    public override func insertBacktab(_ sender: Any?) {
        if let edit = EditingCommands.indent(text: string as NSString, selection: selectedRange(), outdent: true) {
            perform(edit)
        } else {
            super.insertBacktab(sender)
        }
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self, isEditable else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags, key) {
        case ([.command], "b"): toggleBold(nil)
        case ([.command], "i"): toggleItalic(nil)
        case ([.command], "e"): toggleInlineCode(nil)
        case ([.command], "k"): insertMarkdownLink(nil)
        case ([.command, .shift], "x"): toggleStrikethrough(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Rich text from the web pastes as plain text; the styler then applies the editor's own styles.
    /// ⌘⇧⌥V keeps its system meaning (spec §7.5).
    public override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    // MARK: Tasks and links

    /// Flips `[ ]` and `[x]` of the task item at `index` as one undoable edit.
    public func toggleTask(atCharacterIndex index: Int) {
        guard let block = blocks.first(where: { block in
            guard case .listItem(_, let task, _) = block.kind, task != nil else { return false }
            return index >= block.range.location && index <= NSMaxRange(block.range)
        }), case .listItem(_, let task?, _) = block.kind, let syntax = block.syntaxRanges.first else { return }
        let marker = (string as NSString).substring(with: syntax) as NSString
        let bracket = marker.range(of: "[")
        guard bracket.location != NSNotFound else { return }
        let target = NSRange(location: syntax.location + bracket.location + 1, length: 1)
        let replacement = task == .open ? "x" : " "
        guard shouldChangeText(in: target, replacementString: replacement) else { return }
        replaceCharacters(in: target, with: replacement)
        didChangeText()
        undoManager?.setActionName("切换任务")
    }

    /// The drawn checkbox of the task item containing `index`, in view coordinates; nil while it is not drawn.
    public func checkboxRect(forCharacterIndex index: Int) -> NSRect? {
        guard let decoration = decorations.first(where: { decoration in
            guard case .checkbox(let at, _) = decoration, let block = blocks.first(where: { $0.syntaxRanges.first?.location == at }) else { return false }
            return index >= block.range.location && index <= NSMaxRange(block.range)
        }), case .checkbox(let at, _) = decoration else { return nil }
        concealingLayoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length))
        let rect = concealingLayoutManager.gutterRect(forMarkerAt: at, size: theme.bodySize)
        let origin = textContainerOrigin
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// URL of the link or bare URL at `index`, if any.
    public func linkURL(atCharacterIndex index: Int) -> URL? {
        for block in blocks {
            for span in block.inlines where NSLocationInRange(index, span.range) {
                switch span.kind {
                case .link(let url): return URL(string: url)
                case .bareURL(let url): return URL(string: url)
                default: continue
                }
            }
        }
        return nil
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for case .checkbox(let at, _) in decorations {
            if let rect = checkboxRect(forCharacterIndex: at), rect.contains(point) {
                toggleTask(atCharacterIndex: at)
                return
            }
        }
        if event.modifierFlags.contains(.command),
           let url = linkURL(atCharacterIndex: characterIndexForInsertion(at: point)) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    // The pointing hand shows over links only while ⌘ is held.
    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        window?.invalidateCursorRects(for: self)
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        guard NSEvent.modifierFlags.contains(.command) else { return }
        for block in blocks {
            for span in block.inlines {
                switch span.kind {
                case .link, .bareURL:
                    let glyphs = concealingLayoutManager.glyphRange(forCharacterRange: span.range, actualCharacterRange: nil)
                    guard let container = textContainer else { continue }
                    let origin = textContainerOrigin
                    concealingLayoutManager.enumerateEnclosingRects(
                        forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container
                    ) { rect, _ in
                        self.addCursorRect(rect.offsetBy(dx: origin.x, dy: origin.y), cursor: .pointingHand)
                    }
                default:
                    continue
                }
            }
        }
    }

    // MARK: Block geometry and one-step edits (used by the review window)

    /// Replaces `range` as a single undoable edit named `actionName`.
    public func applyEdit(range: NSRange, replacement: String, actionName: String) {
        perform(
            TextEdit(range: range, replacement: replacement, selectionAfter: NSRange(location: range.location + (replacement as NSString).length, length: 0)),
            actionName: actionName
        )
    }

    /// Y position (view coordinates) of the first line of block `index`.
    public func blockTop(at index: Int) -> CGFloat? {
        guard blocks.indices.contains(index), concealingLayoutManager.numberOfGlyphs > 0 else { return nil }
        let location = min(blocks[index].range.location, max((string as NSString).length - 1, 0))
        concealingLayoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length))
        let glyph = concealingLayoutManager.glyphIndexForCharacter(at: location)
        return concealingLayoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + textContainerOrigin.y
    }

    /// The block that is at, or most recently started above, view coordinate `y`; clamped to the document.
    public func blockIndexAt(y: CGFloat) -> Int? {
        guard !blocks.isEmpty else { return nil }
        var result = 0
        for index in blocks.indices {
            guard let top = blockTop(at: index) else { continue }
            if top <= y { result = index } else { break }
        }
        return result
    }

    private func publishBlockLabels() {
        concealingLayoutManager.blockLabels = blockLabels.compactMap { index, label in
            blocks.indices.contains(index) ? (blocks[index].range, label) : nil
        }
        needsDisplay = true
    }

    // MARK: Layout

    /// Sizes the text column to the window (see `EditorTheme.horizontalInset`), 56 pt above the first line.
    /// The bottom padding (40% of the visible height) lives in the scroll view's content insets, because
    /// `textContainerInset` is symmetric.
    private func updateLayoutInsets() {
        let horizontal = fixedHorizontalInset ?? theme.horizontalInset(forWidth: bounds.width)
        let inset = NSSize(width: horizontal, height: 56)
        if textContainerInset != inset { textContainerInset = inset }
        if let scrollView = enclosingScrollView {
            scrollView.automaticallyAdjustsContentInsets = false
            let bottom = (scrollView.contentView.bounds.height * 0.4).rounded(.down)
            if scrollView.contentInsets.bottom != bottom { scrollView.contentInsets.bottom = bottom }
        }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayoutInsets()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateLayoutInsets()
    }

    // MARK: NSTextView overrides

    public override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let allowed = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if allowed { blocksAreStale = true }
        return allowed
    }

    public override func didChangeText() {
        super.didChangeText()
        // Restyling while an input method is composing breaks its candidate window (spec §7.4).
        guard !hasMarkedText() else { return }
        restyleAfterEdit()
        onTextChange?(string)
    }

    public override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        updateActiveBlocks()
    }
}
