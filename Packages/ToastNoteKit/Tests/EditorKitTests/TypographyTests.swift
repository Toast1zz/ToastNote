import AppKit
import Foundation
import Testing
@testable import EditorKit

/// The typography table of spec §9.3, line by line.
@Suite struct TypographyTests {
    private let theme = EditorTheme.default

    private func font(_ role: TextStyle.Role) -> NSFont? {
        theme.attributes(for: TextStyle(role: role))[.font] as? NSFont
    }

    @Test func headingSizes() {
        #expect([1, 2, 3, 4, 5, 6].map { theme.headingSize($0) } == [28, 22, 19, 16, 16, 16])
    }

    @Test func headingSizesScaleWithBodySize() {
        let big = EditorTheme(bodySize: 18)
        #expect(abs(big.headingSize(1) - 33.6) < 0.001)
        #expect(abs(big.headingSize(4) - 19.2) < 0.001)
    }

    @Test func headingWeights() {
        func weight(_ level: Int) -> CGFloat {
            let traits = font(.heading(level))?.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            return traits?[.weight] as? CGFloat ?? 0
        }
        // H1 bold, the rest semibold.
        #expect(weight(1) > weight(2))
        #expect(weight(2) == weight(3))
        #expect(weight(3) == weight(4))
        #expect(weight(2) > 0.2)
    }

    @Test func h1HasTighterLetterSpacing() {
        let h1 = theme.attributes(for: TextStyle(role: .heading(1)))[.kern] as? CGFloat
        #expect(h1 == -0.01 * 28)
        #expect(theme.attributes(for: TextStyle(role: .heading(2)))[.kern] == nil)
    }

    @Test func bodyAndCodeFonts() {
        #expect(font(.body)?.pointSize == 15)
        #expect(font(.codeBlock)?.pointSize == 13)
        #expect(font(.codeBlock)?.isFixedPitch == true)
        #expect(font(.codeInline)?.isFixedPitch == true)
    }

    @Test func headingSpacingFollowsTheTable() {
        func spacing(_ level: Int) -> (before: CGFloat, after: CGFloat) {
            let style = theme.paragraphStyle(for: TextStyle(role: .heading(level)))
            let size = theme.headingSize(level)
            return (style.paragraphSpacingBefore / size, style.paragraphSpacing / size)
        }
        #expect(spacing(1) == (1.2, 0.4))
        #expect(spacing(2) == (1.1, 0.35))
        #expect(spacing(3) == (1.0, 0.3))
        #expect(spacing(4) == (0.9, 0.25))
        #expect(spacing(6) == (0.9, 0.25))
    }

    @Test func bodyParagraphSpacingAndIndents() {
        let body = theme.paragraphStyle(for: TextStyle(role: .body))
        #expect(body.paragraphSpacing == 0.6 * 15)
        #expect(theme.paragraphStyle(for: TextStyle(role: .quote)).headIndent == 16)
        #expect(theme.paragraphStyle(for: TextStyle(role: .codeBlock)).headIndent == 12)
    }

    @Test func colorsAreSystemSemanticColors() {
        func color(_ role: TextStyle.Role) -> NSColor? { theme.attributes(for: TextStyle(role: role))[.foregroundColor] as? NSColor }
        #expect(color(.body) == .labelColor)
        #expect(color(.link) == .controlAccentColor)
        #expect(color(.tag) == .controlAccentColor)
        #expect(color(.marker) == .secondaryLabelColor)
    }
}
