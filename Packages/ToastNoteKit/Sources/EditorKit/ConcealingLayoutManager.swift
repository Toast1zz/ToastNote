import AppKit

/// Hides characters by giving their glyphs the `.null` property (spec §7.2) and draws block decorations.
/// The hidden characters stay in the text storage, so selection, copy and undo still see them.
/// Never shrink fonts or use clear colors instead.
final class ConcealingLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// UTF-16 character indices to hide.
    var hidden = IndexSet()
    var decorations: [Decoration] = []
    var theme = EditorTheme.default
    /// Supplies the image and its display size for an `![](source)` line; set by the text view.
    var imageProvider: (@MainActor (String) -> (image: NSImage, size: NSSize)?)?
    /// Labelled blocks of the review window: a 2 pt accent bar in the gutter plus a small label.
    var blockLabels: [(range: NSRange, label: String)] = []
    /// Column widths of rendered tables, keyed by the table's first character; measured by the text view.
    var tableColumnWidths: [Int: [CGFloat]] = [:]

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

    /// Start of the visible text after the hidden marker at `characterIndex`: its x and baseline.
    private func textStart(afterMarkerAt characterIndex: Int) -> NSPoint {
        let markerEnd = hidden.rangeView.first { $0.contains(characterIndex) }?.upperBound ?? characterIndex + 1
        guard numberOfGlyphs > 0 else { return .zero }
        let glyph = min(glyphIndexForCharacter(at: markerEnd), numberOfGlyphs - 1)
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let position = location(forGlyphAt: glyph)
        return NSPoint(x: fragment.minX + position.x, y: fragment.minY + position.y)
    }

    /// Light wash of the label color; adapts to dark mode (spec §9.4 calls for the quaternary label at 50%,
    /// which `withAlphaComponent` would turn into an opaque-looking gray).
    static var codeWash: NSColor { NSColor.labelColor.withAlphaComponent(0.07) }


    // MARK: Text-relative geometry
    //
    // Line fragments are taller than the text (fixed line heights put the extra space above the glyphs), so
    // backgrounds are measured from the baseline instead of from the line box.

    /// Baseline of the line containing the character at `index`, in container coordinates.
    private func baseline(ofCharacterAt index: Int) -> CGFloat {
        let glyph = min(glyphIndexForCharacter(at: index), max(numberOfGlyphs - 1, 0))
        return lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + location(forGlyphAt: glyph).y
    }

    /// `rect` narrowed vertically to the height of the text on its line.
    private func textHugging(_ rect: NSRect, fontSize: CGFloat, verticalPadding: CGFloat) -> NSRect {
        guard let container = textContainers.first, numberOfGlyphs > 0 else { return rect }
        let glyph = glyphIndex(for: NSPoint(x: rect.midX, y: rect.midY), in: container)
        let baseline = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + location(forGlyphAt: glyph).y
        let top = baseline - 1.0 * fontSize - verticalPadding
        let bottom = baseline + 0.3 * fontSize + verticalPadding
        return NSRect(x: rect.minX, y: top, width: rect.width, height: bottom - top)
    }

    /// Left edge of the text column inside the container; boxes, rules and pictures line up with it.
    private var columnLeft: CGFloat { textContainers.first?.lineFragmentPadding ?? 0 }

    /// Width of the text column.
    private var columnWidth: CGFloat { max((textContainers.first?.size.width ?? 0) - 2 * columnLeft, 0) }

    /// Column-wide box for a code block with equal padding above the first and below the last line of text.
    private func codeBackgroundRect(for range: NSRange) -> NSRect? {
        guard numberOfGlyphs > 0, range.length > 0 else { return nil }
        let codeSize = 13 * theme.bodySize / 15
        let padding: CGFloat = 8
        // Fence lines are hidden while the block is inactive; measure from the first and last visible line.
        var first = range.location
        while first < NSMaxRange(range) - 1, hidden.contains(first) { first += 1 }
        var last = NSMaxRange(range) - 1
        while last > first, hidden.contains(last) { last -= 1 }
        let top = baseline(ofCharacterAt: first) - 1.0 * codeSize - padding
        let bottom = baseline(ofCharacterAt: last) + 0.3 * codeSize + padding
        return NSRect(x: columnLeft, y: top, width: columnWidth, height: bottom - top)
    }

    // MARK: Drawing

    /// Gutter bars and labels of the review window. NSTextView clips layout-manager drawing to the text
    /// container, and the gutter lies outside it, so the view calls this from its own `draw(_:)`.
    func drawBlockLabels(at origin: NSPoint) {
        guard !blockLabels.isEmpty, numberOfGlyphs > 0 else { return }
        let accent = NSColor.controlAccentColor
        for (range, label) in blockLabels {
            let rects = lineRects(for: range)
            guard let first = rects.first, let last = rects.last else { continue }
            let bar = NSRect(x: -12, y: first.minY, width: 2, height: last.maxY - first.minY)
            fill(bar, origin: origin, radius: 1, color: accent)
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: accent]
            let size = (label as NSString).size(withAttributes: attributes)
            // Right-aligned against the bar, level with the first line of text.
            let baseline = self.baseline(ofCharacterAt: range.location)
            (label as NSString).draw(
                at: NSPoint(x: origin.x - 18 - size.width, y: origin.y + baseline - size.height * 0.8),
                withAttributes: attributes
            )
        }
    }


    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard !decorations.isEmpty, let container = textContainers.first else { return }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let accent = NSColor.controlAccentColor

        for decoration in decorations {
            switch decoration {
            case .codeBackground(let range):
                guard intersects(range, visible), let rect = codeBackgroundRect(for: range) else { continue }
                fill(rect, origin: origin, radius: 6, color: Self.codeWash)
            case .codeLanguage(let language, let range):
                guard intersects(range, visible), let box = codeBackgroundRect(for: range) else { continue }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor,
                ]
                let size = (language as NSString).size(withAttributes: attributes)
                (language as NSString).draw(
                    at: NSPoint(x: origin.x + box.maxX - size.width - 10, y: origin.y + box.minY + 5),
                    withAttributes: attributes
                )
            case .inlineCodeBackground(let range):
                guard intersects(range, visible) else { continue }
                for rect in enclosingRects(for: range) {
                    let box = textHugging(rect, fontSize: theme.bodySize, verticalPadding: 1).insetBy(dx: -2, dy: 0)
                    fill(box, origin: origin, radius: 4, color: Self.codeWash)
                }
            case .tagPill(let range):
                guard intersects(range, visible) else { continue }
                for rect in enclosingRects(for: range) {
                    let pill = textHugging(rect, fontSize: theme.bodySize, verticalPadding: 1).insetBy(dx: -4, dy: 0)
                    fill(pill, origin: origin, radius: pill.height / 2, color: accent.withAlphaComponent(0.12))
                }
            case .quoteBar(let range):
                guard intersects(range, visible) else { continue }
                let rects = lineRects(for: range)
                guard let first = rects.first, let last = rects.last else { continue }
                let bar = NSRect(x: columnLeft, y: first.minY, width: 3, height: last.maxY - first.minY)
                fill(bar, origin: origin, radius: 1.5, color: accent.withAlphaComponent(0.4))
            case .rule(let range):
                guard intersects(range, visible), let first = lineRects(for: NSRange(location: range.location, length: 1)).first else { continue }
                let line = NSRect(x: columnLeft, y: first.midY - 0.5, width: columnWidth, height: 1)
                fill(line, origin: origin, radius: 0, color: NSColor.separatorColor)
            case .bullet(let at, let depth):
                guard NSLocationInRange(at, visible) else { continue }
                drawBullet(markerAt: at, depth: depth, origin: origin)
            case .orderedNumber(let number, let at, _):
                guard NSLocationInRange(at, visible) else { continue }
                drawNumber(number, markerAt: at, origin: origin)
            case .table(let layout):
                guard intersects(layout.range, visible) else { continue }
                drawTable(layout, origin: origin, containerWidth: container.size.width)
            case .checkbox(let at, let done):
                guard NSLocationInRange(at, visible) else { continue }
                drawCheckbox(markerAt: at, done: done, origin: origin)
            case .frontmatterSummary(let count, let lineRange):
                guard intersects(lineRange, visible), let first = lineRects(for: lineRange).first else { continue }
                drawFrontmatterSummary(count: count, line: first, origin: origin)
            case .image(let source, let lineRange):
                guard intersects(lineRange, visible), let line = lineRects(for: lineRange).first, let provider = imageProvider,
                      let content = MainActor.assumeIsolated({ provider(source) }) else { continue }
                // The line is as tall as the picture (plus a margin), so the picture fills its own line.
                let rect = NSRect(x: columnLeft, y: line.minY + 6, width: content.size.width, height: content.size.height)
                let target = rect.offsetBy(dx: origin.x, dy: origin.y)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: target, xRadius: 6, yRadius: 6).addClip()
                content.image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
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

    private var markerColor: NSColor { theme.increasedContrast ? .labelColor : .secondaryLabelColor }

    /// A filled dot, then a ring, then a small square for deeper levels, so nesting reads at a glance.
    private func drawBullet(markerAt index: Int, depth: Int, origin: NSPoint) {
        let size = theme.bodySize
        let rect = gutterRect(forMarkerAt: index, size: size).offsetBy(dx: origin.x, dy: origin.y)
        let diameter = size * 0.3
        // The mark sits in the right half of the gutter, next to the text.
        let mark = NSRect(x: rect.maxX - diameter - 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        markerColor.set()
        switch depth % 3 {
        case 0:
            NSBezierPath(ovalIn: mark).fill()
        case 1:
            let ring = NSBezierPath(ovalIn: mark.insetBy(dx: 0.6, dy: 0.6))
            ring.lineWidth = 1.2
            ring.stroke()
        default:
            NSBezierPath(rect: mark.insetBy(dx: 0.4, dy: 0.4)).fill()
        }
    }

    /// The item number, right-aligned in the gutter on the text's baseline, with tabular digits so a column of
    /// numbers lines up.
    private func drawNumber(_ number: String, markerAt index: Int, origin: NSPoint) {
        let start = textStart(afterMarkerAt: index)
        let font = NSFont.monospacedDigitSystemFont(ofSize: theme.bodySize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: markerColor]
        let width = (number as NSString).size(withAttributes: attributes).width
        let right = start.x - 0.35 * theme.bodySize
        (number as NSString).draw(
            at: NSPoint(x: origin.x + right - width, y: origin.y + start.y - font.ascender),
            withAttributes: attributes
        )
    }

    /// "属性 · n 项" as a quiet capsule on the frontmatter's own line.
    private func drawFrontmatterSummary(count: Int, line: NSRect, origin: NSPoint) {
        let text = "属性 · \(count) 项" as NSString
        let font = NSFont.systemFont(ofSize: 12 * theme.bodySize / 15)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: markerColor]
        let size = text.size(withAttributes: attributes)
        let pill = NSRect(x: columnLeft, y: line.midY - size.height / 2 - 3, width: size.width + 16, height: size.height + 6)
        fill(pill, origin: origin, radius: pill.height / 2, color: Self.codeWash)
        text.draw(at: NSPoint(x: origin.x + pill.minX + 8, y: origin.y + pill.minY + 3), withAttributes: attributes)
    }

    /// A rounded box with a tinted header, rules between rows and columns. Rows are measured from their
    /// baselines (line boxes carry their extra height above the text).
    private func drawTable(_ layout: TableLayout, origin: NSPoint, containerWidth: CGFloat) {
        guard let columns = tableColumnWidths[layout.range.location], !columns.isEmpty, !layout.rows.isEmpty, numberOfGlyphs > 0 else { return }
        let size = theme.bodySize
        let gap = 2 * theme.codePadding
        // A row spans from the baseline of its first line to the baseline of its last (rows can wrap).
        let firstBaselines = layout.rows.map { row -> CGFloat in
            let anchor = row.cells.first { $0.length > 0 }?.location ?? row.spacers.first ?? row.line.location
            return baseline(ofCharacterAt: anchor)
        }
        let lastBaselines = layout.rows.enumerated().map { index, row -> CGFloat in
            guard let last = row.cells.last(where: { $0.length > 0 }) else { return firstBaselines[index] }
            return max(baseline(ofCharacterAt: NSMaxRange(last) - 1), firstBaselines[index])
        }
        let pad = 0.35 * size
        let top = firstBaselines[0] - 1.0 * size - pad
        let bottom = lastBaselines[lastBaselines.count - 1] + 0.3 * size + pad
        let firstCell = layout.rows[0].cells.first { $0.length > 0 }?.location ?? layout.rows[0].line.location
        let textX = textStart(afterMarkerAt: max(firstCell - 1, layout.range.location)).x
        let left = max(textX - theme.codePadding, 0)
        let contentWidth = columns.reduce(0, +) + gap * CGFloat(columns.count - 1)
        let box = NSRect(x: left, y: top, width: min(contentWidth + 2 * theme.codePadding, containerWidth - left), height: bottom - top)
        let moved = box.offsetBy(dx: origin.x, dy: origin.y)
        let outline = NSBezierPath(roundedRect: moved.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        func separator(after index: Int) -> CGFloat {
            (lastBaselines[index] + 0.3 * size + firstBaselines[index + 1] - 1.0 * size) / 2
        }
        if layout.rows.count > 1 {
            let headerBottom = separator(after: 0)
            fill(NSRect(x: box.minX, y: box.minY, width: box.width, height: headerBottom - box.minY), origin: origin, radius: 0, color: Self.codeWash)
        }
        let rule = NSColor.separatorColor
        for index in 1..<max(layout.rows.count, 1) {
            let y = separator(after: index - 1)
            fill(NSRect(x: box.minX, y: y - 0.5, width: box.width, height: 1), origin: origin, radius: 0, color: rule)
        }
        var x = textX
        for width in columns.dropLast() {
            x += width + gap
            fill(NSRect(x: x - gap / 2 - 0.5, y: box.minY, width: 1, height: box.height), origin: origin, radius: 0, color: rule)
        }
        NSGraphicsContext.restoreGraphicsState()
        rule.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    private func drawCheckbox(markerAt index: Int, done: Bool, origin: NSPoint) {
        let size = theme.bodySize
        let rect = gutterRect(forMarkerAt: index, size: size).offsetBy(dx: origin.x, dy: origin.y)
        let name = done ? "checkmark.square.fill" : "square"
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: done ? "已完成" : "未完成") else { return }
        // Palette: the first color is the checkmark, the second the filled square.
        let colors: [NSColor] = done ? [.white, .controlAccentColor] : [theme.increasedContrast ? .labelColor : .secondaryLabelColor]
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(.init(paletteColors: colors))
        image.withSymbolConfiguration(configuration)?.draw(in: rect)
    }
}
