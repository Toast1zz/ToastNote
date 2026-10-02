import AppKit

/// Hides characters by giving their glyphs the `.null` property (spec §7.2) and draws block decorations.
/// The hidden characters stay in the text storage, so selection, copy and undo still see them.
/// Never shrink fonts or use clear colors instead.
final class ConcealingLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// UTF-16 character indices to hide.
    var hidden = IndexSet()
    var decorations: [Decoration] = []
    var theme = EditorTheme.default

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !hidden.isEmpty else { return 0 }
        var properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var changed = false
        for index in 0..<glyphRange.length where hidden.contains(charIndexes[index]) {
            properties[index] = .null
            changed = true
        }
        // Returning 0 lets AppKit generate the glyphs normally.
        guard changed else { return 0 }
        layoutManager.setGlyphs(glyphs, properties: properties, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    /// Keeps `hidden` aligned with the text while an edit is processed. AppKit may generate glyphs for the
    /// shifted text before the view has restyled; with stale indices the wrong characters would be hidden.
    override func processEditing(
        for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange,
        changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange
    ) {
        if editMask.contains(.editedCharacters), !hidden.isEmpty {
            let oldEnd = newCharRange.location + newCharRange.length - delta
            hidden.remove(integersIn: newCharRange.location..<max(oldEnd, newCharRange.location))
            hidden.shift(startingAt: max(oldEnd, newCharRange.location), by: delta)
        }
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
    }

    // MARK: Geometry (text container coordinates)

    /// Line fragments covering `characterRange`, as used rects.
    private func lineRects(for characterRange: NSRange) -> [NSRect] {
        let glyphRange = self.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            // An empty (fully hidden) range still sits on a line fragment.
            guard numberOfGlyphs > 0 else { return [] }
            let glyph = min(glyphIndexForCharacter(at: characterRange.location), numberOfGlyphs - 1)
            return [lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)]
        }
        var rects: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in rects.append(usedRect) }
        return rects
    }

    /// Where a bullet or checkbox for the hidden marker at `characterIndex` is drawn, in container
    /// coordinates: just left of the first visible character after the marker, centered on the x-height.
    /// (Positions of hidden `.null` glyphs are not reliable, so the visible glyph is used.)
    func gutterRect(forMarkerAt characterIndex: Int, size: CGFloat) -> NSRect {
        let markerEnd = hidden.rangeView.first { $0.contains(characterIndex) }?.upperBound ?? characterIndex + 1
        guard numberOfGlyphs > 0 else { return .zero }
        let glyph = min(glyphIndexForCharacter(at: markerEnd), numberOfGlyphs - 1)
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let position = location(forGlyphAt: glyph)
        let textX = fragment.minX + position.x
        let baseline = fragment.minY + position.y
        return NSRect(
            x: textX - size - 0.3 * theme.bodySize,
            y: baseline - 0.35 * theme.bodySize - size / 2,
            width: size, height: size
        )
    }

    /// Light wash of the label color; adapts to dark mode (spec §9.4 calls for the quaternary label at 50%,
    /// which `withAlphaComponent` would turn into an opaque-looking gray).
    static var codeWash: NSColor { NSColor.labelColor.withAlphaComponent(0.07) }

    // MARK: Drawing

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard !decorations.isEmpty, let container = textContainers.first else { return }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let accent = NSColor.controlAccentColor

        for decoration in decorations {
            switch decoration {
            case .codeBackground(let range):
                guard intersects(range, visible) else { continue }
                let rects = lineRects(for: range)
                guard let first = rects.first, let last = rects.last else { continue }
                let rect = NSRect(x: 0, y: first.minY - 6, width: container.size.width, height: last.maxY - first.minY + 12)
                fill(rect, origin: origin, radius: 6, color: Self.codeWash)
            case .codeLanguage(let language, let range):
                guard intersects(range, visible), let first = lineRects(for: range).first else { continue }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor,
                ]
                let size = (language as NSString).size(withAttributes: attributes)
                (language as NSString).draw(
                    at: NSPoint(x: origin.x + container.size.width - size.width - theme.codePadding, y: origin.y + first.minY - 2),
                    withAttributes: attributes
                )
            case .inlineCodeBackground(let range):
                guard intersects(range, visible) else { continue }
                for rect in enclosingRects(for: range) {
                    fill(rect.insetBy(dx: -2, dy: 1), origin: origin, radius: 4, color: Self.codeWash)
                }
            case .tagPill(let range):
                guard intersects(range, visible) else { continue }
                for rect in enclosingRects(for: range) {
                    let pill = rect.insetBy(dx: -3, dy: 1)
                    fill(pill, origin: origin, radius: pill.height / 2, color: accent.withAlphaComponent(0.12))
                }
            case .quoteBar(let range):
                guard intersects(range, visible) else { continue }
                let rects = lineRects(for: range)
                guard let first = rects.first, let last = rects.last else { continue }
                let bar = NSRect(x: 4, y: first.minY, width: 3, height: last.maxY - first.minY)
                fill(bar, origin: origin, radius: 1.5, color: accent.withAlphaComponent(0.4))
            case .rule(let range):
                guard intersects(range, visible), let first = lineRects(for: range).first else { continue }
                let line = NSRect(x: 0, y: first.midY - 0.5, width: container.size.width, height: 1)
                fill(line, origin: origin, radius: 0, color: NSColor.separatorColor)
            case .bullet(let at, _):
                guard NSLocationInRange(at, visible) else { continue }
                drawBullet(markerAt: at, origin: origin)
            case .checkbox(let at, let done):
                guard NSLocationInRange(at, visible) else { continue }
                drawCheckbox(markerAt: at, done: done, origin: origin)
            case .frontmatterSummary(let count, let lineRange):
                guard intersects(lineRange, visible), let first = lineRects(for: lineRange).first else { continue }
                let text = "属性 · \(count) 项" as NSString
                let attributes: [NSAttributedString.Key: Any] = theme.attributes(for: TextStyle(role: .frontmatterSummary))
                text.draw(at: NSPoint(x: origin.x + first.minX, y: origin.y + first.minY), withAttributes: attributes)
            case .image:
                break  // Drawn by the image pass (Task 31).
            }
        }
    }

    private func intersects(_ range: NSRange, _ visible: NSRange) -> Bool {
        NSIntersectionRange(range, visible).length > 0 || NSLocationInRange(range.location, visible)
    }

    private func enclosingRects(for characterRange: NSRange) -> [NSRect] {
        guard let container = textContainers.first else { return [] }
        let glyphRange = self.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        var rects: [NSRect] = []
        enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
            rects.append(rect)
        }
        return rects
    }

    private func fill(_ rect: NSRect, origin: NSPoint, radius: CGFloat, color: NSColor) {
        color.setFill()
        let moved = rect.offsetBy(dx: origin.x, dy: origin.y)
        if radius > 0 {
            NSBezierPath(roundedRect: moved, xRadius: radius, yRadius: radius).fill()
        } else {
            moved.fill()
        }
    }

    private func drawBullet(markerAt index: Int, origin: NSPoint) {
        let size = theme.bodySize
        let rect = gutterRect(forMarkerAt: index, size: size).offsetBy(dx: origin.x, dy: origin.y)
        let diameter = size * 0.3
        NSColor.secondaryLabelColor.setFill()
        // The dot sits in the right half of the gutter, next to the text.
        NSBezierPath(ovalIn: NSRect(x: rect.maxX - diameter - 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)).fill()
    }

    private func drawCheckbox(markerAt index: Int, done: Bool, origin: NSPoint) {
        let size = theme.bodySize
        let rect = gutterRect(forMarkerAt: index, size: size).offsetBy(dx: origin.x, dy: origin.y)
        let name = done ? "checkmark.square.fill" : "square"
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: done ? "已完成" : "未完成") else { return }
        // Palette: the first color is the checkmark, the second the filled square.
        let colors: [NSColor] = done ? [.white, .controlAccentColor] : [.secondaryLabelColor]
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(.init(paletteColors: colors))
        image.withSymbolConfiguration(configuration)?.draw(in: rect)
    }
}
