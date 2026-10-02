import AppKit

/// Hides characters by giving their glyphs the `.null` property (spec §7.2). The characters stay in the
/// text storage, so selection, copy and undo still see them. Never shrink fonts or use clear colors instead.
final class ConcealingLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// UTF-16 character indices to hide.
    var hidden = IndexSet()

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
}
