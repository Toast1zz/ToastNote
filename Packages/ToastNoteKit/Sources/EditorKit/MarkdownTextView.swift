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
    /// Decorations to draw (Task 13).
    private(set) var decorations: [Decoration] = []

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
            undoManager?.disableUndoRegistration()
            string = newValue
            undoManager?.enableUndoRegistration()
            undoManager?.removeAllActions()
            restyleAll()
        }
    }

    // MARK: Restyling

    public func restyleAll() {
        let signpost = EditorSignposts.signposter
        let state = signpost.beginInterval("restyle")
        defer { signpost.endInterval("restyle", state) }

        let text = string as NSString
        blocks = BlockParser.parse(string)
        activeBlocks = concealAll ? [] : blocks.indices(intersecting: selectedRange())
        let result = MarkdownStyler.style(blocks: blocks, text: text, active: activeBlocks, concealAll: concealAll)
        apply(result, in: NSRange(location: 0, length: text.length))
        restyleCount += 1
    }

    /// Writes styles for `range` and publishes the hidden set. Attribute-only edits never touch undo.
    private func apply(_ result: StyleResult, in range: NSRange) {
        guard let storage = textStorage else { return }
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }

        let base = theme.attributes(for: TextStyle(role: .body))
        storage.beginEditing()
        storage.setAttributes(base, range: range)
        for run in result.runs {
            let clipped = NSIntersectionRange(run.range, range)
            if clipped.length > 0 { storage.addAttributes(theme.attributes(for: run.style), range: clipped) }
        }
        concealingLayoutManager.hidden = result.hidden.reduce(into: IndexSet()) { set, hidden in
            if hidden.length > 0 { set.insert(integersIn: hidden.location..<NSMaxRange(hidden)) }
        }
        storage.endEditing()
        concealingLayoutManager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        concealingLayoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        decorations = result.decorations
        concealingLayoutManager.decorations = result.decorations
        concealingLayoutManager.theme = theme
        typingAttributes = base
        needsDisplay = true
    }

    /// Caret moved: only blocks whose active state changed need new glyphs and attributes.
    private func updateActiveBlocks() {
        guard !concealAll, !hasMarkedText() else { return }
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
    }

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

    // MARK: Layout

    /// Centers the text column at `maxContentWidth` (at least 48 pt on each side), 56 pt above the first line.
    /// The bottom padding (40% of the visible height) lives in the scroll view's content insets, because
    /// `textContainerInset` is symmetric.
    private func updateLayoutInsets() {
        let horizontal = max(48, ((bounds.width - theme.maxContentWidth) / 2).rounded(.down))
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

    public override func didChangeText() {
        super.didChangeText()
        // Restyling while an input method is composing breaks its candidate window (spec §7.4).
        guard !hasMarkedText() else { return }
        restyleAll()
        onTextChange?(string)
    }

    public override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        updateActiveBlocks()
    }
}
